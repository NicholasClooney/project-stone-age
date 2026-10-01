/* 本机极速模式: the pet hunt scan (client/server/automation.gd scan_once) in C,
 * across all CPU cores.
 *
 * Every hunt roll i has its own Godot RandomNumberGenerator seeded with
 * roll_seed(run_seed, i) (splitmix64 of run_seed + (i+1)*golden gamma), so rolls
 * are independent and can be scanned in parallel. For each roll this program
 * reproduces exactly what the backend does:
 *   - Godot 4.6 RandomPCG: pcg32 with the default increment, seeding by
 *     pcg32_srandom_r, randi_range(a,b) = bounded(|a-b|+1) + min(a,b) with
 *     modulo rejection, and randi_range(a,a) returning a without a draw;
 *   - encounter_catalog.gd roll() and actor() for the hunt's area;
 *   - scan_once's filters, HuntRules.matches and, during a find-pet cycle,
 *     accepts_prediction: Progression.project_pet to Lv120 and StatFilter.evaluate.
 * The backend re-rolls a reported hit in GDScript before acting on it, and
 * tools/fast_hunt tests compare this program with GDScript roll by roll.
 *
 * Usage: fast_hunt INPUT STATUS
 *   INPUT   written by fast_hunt.gd _input (fasthunt 2). Groups are filtered
 *           against the owning server profile's original_items before writing;
 *           enemy rows include enabled drop RNG draw counts.
 *   STATUS  rewritten atomically about ten times a second, one line:
 *     KIND INDEX SLOT INSPECTED BEST PRED_REJECTS BEST_SUM BEST_ATTACK
 *   KIND is progress (INDEX = next roll to commit), then finally one of
 *     hit    roll INDEX is taken, at enemy SLOT
 *     stop   roll INDEX gives an empty troop (the backend's replay stops the hunt)
 *     limit  the roll limit INDEX was reached
 *   The counters always cover rolls [START, INDEX).
 *   During a survey (摸底) further lines follow, one per candidate kept so far:
 *     cand INDEX SLOT TEMPLATE SUM ATTACK DEFENCE SPEED MAX_HP
 *   With --roll N it prints roll N (troop and projections) and exits: used by tests.
 *
 * Survey (the optional last input section): for the listed species the scan
 * has no Lv120 threshold. Every pet of theirs that passes the grade filter is
 * a candidate instead of a hit, and the scan goes on until the backend stops
 * it. The pool keeps what the species' 保留规则 (client/scripts/keep_rule.gd)
 * would keep of all candidates so far: in each of the top TIERS distinct sums
 * the best PER_TIER by the rule's order, and the best CHAMPIONS per chosen
 * stat. Adding candidates never brings back one the rule dropped, so pruning
 * the pool as it grows keeps exactly that set.
 *
 * Build: cc -O2 -pthread -o build/fast_hunt tools/fast_hunt/fast_hunt.c
 * Windows (MinGW-w64 gcc, winpthreads): add -static and -lshell32 and name it
 * build/fast_hunt.exe; scripts/build-fast-hunt.sh does both.
 */
#ifdef _WIN32
#define __USE_MINGW_ANSI_STDIO 1
#endif
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <time.h>

/* ---- Platform ---------------------------------------------------------------
 * Paths arrive as UTF-8 (Godot's user folder contains the project's Chinese
 * name), the status file is replaced atomically while Godot may be reading
 * it, and the helper stops when the backend that started it is gone. */
#ifdef _WIN32
#include <windows.h>
#include <shellapi.h>
#include <tlhelp32.h>
#include <fcntl.h>
#include <io.h>
static wchar_t *wide(const char *text) {
    int n = MultiByteToWideChar(CP_UTF8, 0, text, -1, NULL, 0);
    wchar_t *w = calloc(n > 0 ? n : 1, sizeof *w);
    if (n > 0) MultiByteToWideChar(CP_UTF8, 0, text, -1, w, n);
    return w;
}
static FILE *open_file(const char *path, const char *mode) {
    wchar_t *w = wide(path), *m = wide(mode);
    FILE *f = _wfopen(w, m);
    free(w); free(m);
    return f;
}
/* Godot opens the status file without FILE_SHARE_DELETE, so a replace can
 * fail for the moment it is being read: retry briefly. */
static void replace_file(const char *from, const char *to) {
    wchar_t *a = wide(from), *b = wide(to);
    for (int attempt = 0; attempt < 200; attempt++) {
        if (MoveFileExW(a, b, MOVEFILE_REPLACE_EXISTING)) break;
        Sleep(5);
    }
    free(a); free(b);
}
static int cpu_count(void) { SYSTEM_INFO info; GetSystemInfo(&info); return (int)info.dwNumberOfProcessors; }
static HANDLE parent_process;
static void watch_parent(void) {
    DWORD self = GetCurrentProcessId(), parent = 0;
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    PROCESSENTRY32W entry; entry.dwSize = sizeof entry;
    if (snapshot != INVALID_HANDLE_VALUE && Process32FirstW(snapshot, &entry)) {
        do { if (entry.th32ProcessID == self) { parent = entry.th32ParentProcessID; break; } } while (Process32NextW(snapshot, &entry));
    }
    if (snapshot != INVALID_HANDLE_VALUE) CloseHandle(snapshot);
    parent_process = parent ? OpenProcess(SYNCHRONIZE, FALSE, parent) : NULL;
}
static int parent_gone(void) { return parent_process && WaitForSingleObject(parent_process, 0) == WAIT_OBJECT_0; }
/* argv in UTF-8 instead of the ANSI code page. */
static char **utf8_arguments(int *argc) {
    wchar_t **w = CommandLineToArgvW(GetCommandLineW(), argc);
    char **out = calloc(*argc + 1, sizeof *out);
    for (int i = 0; i < *argc; i++) {
        int n = WideCharToMultiByte(CP_UTF8, 0, w[i], -1, NULL, 0, NULL, NULL);
        out[i] = calloc(n > 0 ? n : 1, 1);
        if (n > 0) WideCharToMultiByte(CP_UTF8, 0, w[i], -1, out[i], n, NULL, NULL);
    }
    LocalFree(w);
    return out;
}
#else
#include <unistd.h>
static FILE *open_file(const char *path, const char *mode) { return fopen(path, mode); }
static void replace_file(const char *from, const char *to) { rename(from, to); }
static int cpu_count(void) { return (int)sysconf(_SC_NPROCESSORS_ONLN); }
static pid_t parent_process;
static void watch_parent(void) { parent_process = getppid(); }
static int parent_gone(void) { return getppid() != parent_process; }
#endif

/* ---- Godot RandomPCG ------------------------------------------------------ */
typedef struct { uint64_t state, inc; } Rng;
static inline uint32_t rng_next(Rng *r) {
    uint64_t o = r->state;
    r->state = o * 6364136223846793005ULL + r->inc;
    uint32_t x = (uint32_t)(((o >> 18u) ^ o) >> 27u), rot = (uint32_t)(o >> 59u);
    return (x >> rot) | (x << ((-rot) & 31));
}
static inline void rng_seed(Rng *r, uint64_t seed) {
    r->state = 0; r->inc = (1442695040888963407ULL << 1u) | 1u;
    rng_next(r); r->state += seed; rng_next(r);
}
static inline uint32_t rng_bounded(Rng *r, uint32_t bound) {
    uint32_t threshold = (-bound) % bound;
    for (;;) { uint32_t v = rng_next(r); if (v >= threshold) return v % bound; }
}
static inline int64_t randi_range(Rng *r, int64_t a, int64_t b) {
    if (a == b) return a;
    int64_t lo = a < b ? a : b, d = a < b ? b - a : a - b;
    return (int64_t)rng_bounded(r, (uint32_t)d + 1u) + lo;
}
static inline uint64_t roll_seed(uint64_t run_seed, uint64_t index) {
    uint64_t z = run_seed + (index + 1) * 0x9E3779B97F4A7C15ULL;
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
    return z ^ (z >> 31);
}

/* ---- input ---------------------------------------------------------------- */
#define MAXE 64
typedef struct { int id, weight, invalid, n; int enemy[MAXE], eweight[MAXE]; } Group;
typedef struct { int id, template_id, level_min, level_max, max_count, pet_flag, t, drop_draws; } Enemy;
typedef struct { int id, initial, wild_growth, size, w[4], rank; } Template;
typedef struct { int enabled, any; int on[4]; double value[4]; int strict[4]; } StatFilter;

static uint64_t run_seed; static int64_t start_index, limit_index; static int threads, max_enemies;
static int ngroups, nenemies, ntemplates; static Group *groups; static Enemy *enemies; static Template *templates;
static int f_template, f_level_one, f_total, f_offsets[4], f_has_offsets, nusable, *usable, flow;
static int nstat; static int *stat_template; static StatFilter *stat_filters;

/* Survey: per species the keep rule; keys index {sum, attack, defence, speed, max_hp}. */
typedef struct { int template_id, tiers, per_tier, champions, norder, order[5], champion[4]; } SurveyRule;
typedef struct { int64_t index; int slot, template_id, st[5]; } Candidate;
static int nsurvey; static SurveyRule *survey_rules;
static Candidate *pool; static int pool_size, pool_capacity;
static pthread_mutex_t pool_lock = PTHREAD_MUTEX_INITIALIZER;

static int find_enemy(int id) { for (int i = 0; i < nenemies; i++) if (enemies[i].id == id) return i; return -1; }
static int find_template(int id) { for (int i = 0; i < ntemplates; i++) if (templates[i].id == id) return i; return -1; }

static void need(FILE *f, const char *word) {
    char got[64];
    if (fscanf(f, "%63s", got) != 1 || strcmp(got, word)) { fprintf(stderr, "input: expected %s\n", word); exit(2); }
}
static long long num(FILE *f) { long long v; if (fscanf(f, "%lld", &v) != 1) { fprintf(stderr, "input: number expected\n"); exit(2); } return v; }
static double real(FILE *f) { double v; if (fscanf(f, "%lf", &v) != 1) { fprintf(stderr, "input: number expected\n"); exit(2); } return v; }

static void read_stat(FILE *f, StatFilter *s) {
    s->enabled = (int)num(f); s->any = (int)num(f);
    for (int m = 0; m < 4; m++) { s->on[m] = (int)num(f); s->value[m] = real(f); s->strict[m] = (int)num(f); }
}

static void load(const char *path) {
    FILE *f = open_file(path, "r");
    if (!f) { perror(path); exit(2); }
    need(f, "fasthunt"); if (num(f) != 2) { fprintf(stderr, "input: version\n"); exit(2); }
    need(f, "run_seed"); run_seed = (uint64_t)num(f);
    need(f, "start"); start_index = num(f);
    need(f, "limit"); limit_index = num(f);
    need(f, "threads"); threads = (int)num(f);
    need(f, "max_enemies"); max_enemies = (int)num(f);
    need(f, "groups"); ngroups = (int)num(f); groups = calloc(ngroups + 1, sizeof *groups);
    for (int i = 0; i < ngroups; i++) {
        Group *g = &groups[i];
        g->id = (int)num(f); g->weight = (int)num(f); g->invalid = (int)num(f); g->n = (int)num(f);
        if (g->n > MAXE) { fprintf(stderr, "input: group too large\n"); exit(2); }
        for (int j = 0; j < g->n; j++) { g->enemy[j] = (int)num(f); g->eweight[j] = (int)num(f); }
    }
    need(f, "enemies"); nenemies = (int)num(f); enemies = calloc(nenemies + 1, sizeof *enemies);
    for (int i = 0; i < nenemies; i++) {
        Enemy *e = &enemies[i];
        e->id = (int)num(f); e->template_id = (int)num(f); e->level_min = (int)num(f); e->level_max = (int)num(f);
        e->max_count = (int)num(f); e->pet_flag = (int)num(f); e->drop_draws = (int)num(f);
    }
    need(f, "templates"); ntemplates = (int)num(f); templates = calloc(ntemplates + 1, sizeof *templates);
    for (int i = 0; i < ntemplates; i++) {
        Template *t = &templates[i];
        t->id = (int)num(f); t->initial = (int)num(f); t->wild_growth = (int)num(f); t->size = (int)num(f);
        int total = 0;
        for (int k = 0; k < 4; k++) { t->w[k] = (int)num(f); total += t->w[k]; }
        const int bands[6] = {100, 95, 90, 85, 80, 0};
        t->rank = 5;
        for (int k = 0; k < 6; k++) if (total >= bands[k]) { t->rank = k; break; }
    }
    for (int i = 0; i < nenemies; i++) enemies[i].t = find_template(enemies[i].template_id);
    need(f, "filter");
    f_template = (int)num(f); f_level_one = (int)num(f); f_total = (int)num(f); f_has_offsets = (int)num(f);
    for (int k = 0; k < 4; k++) f_offsets[k] = (int)num(f);
    nusable = (int)num(f); usable = calloc(nusable + 1, sizeof *usable);
    for (int i = 0; i < nusable; i++) usable[i] = (int)num(f);
    need(f, "flow"); flow = (int)num(f);
    need(f, "stat_filters"); nstat = (int)num(f);
    stat_template = calloc(nstat + 1, sizeof *stat_template); stat_filters = calloc(nstat + 1, sizeof *stat_filters);
    for (int i = 0; i < nstat; i++) { stat_template[i] = (int)num(f); read_stat(f, &stat_filters[i]); }
    /* Optional: survey N, then per species
     *   TEMPLATE TIERS PER_TIER CHAMPIONS NORDER KEY... NCHAMP STAT...
     * KEY 0..4 = sum attack defence speed max_hp (the full comparison order);
     * STAT 1..4 = attack defence speed max_hp. */
    char word[64];
    if (fscanf(f, "%63s", word) == 1) {
        if (strcmp(word, "survey")) { fprintf(stderr, "input: expected survey\n"); exit(2); }
        nsurvey = (int)num(f); survey_rules = calloc(nsurvey + 1, sizeof *survey_rules);
        for (int i = 0; i < nsurvey; i++) {
            SurveyRule *s = &survey_rules[i];
            s->template_id = (int)num(f); s->tiers = (int)num(f); s->per_tier = (int)num(f); s->champions = (int)num(f);
            s->norder = (int)num(f);
            if (s->norder < 0 || s->norder > 5) { fprintf(stderr, "input: survey order\n"); exit(2); }
            for (int k = 0; k < s->norder; k++) s->order[k] = (int)num(f);
            int nchamp = (int)num(f);
            for (int k = 0; k < nchamp; k++) { int stat = (int)num(f); if (stat >= 1 && stat <= 4) s->champion[stat - 1] = 1; }
        }
    }
    fclose(f);
}

/* ---- one roll ------------------------------------------------------------- */
typedef struct { int enemy, level, weights[4], can_capture; int64_t base[4]; uint32_t growth_seed; } Actor;
typedef struct { int count; Actor a[10]; } Troop;
typedef struct { uint64_t inspected, pred_rejects; int best, best_sum, best_attack; } Tally;

/* encounter_catalog._weighted: -1 when the total weight is not positive. */
static int weighted_group(Rng *r) {
    int total = 0;
    for (int i = 0; i < ngroups; i++) total += groups[i].weight > 0 ? groups[i].weight : 0;
    if (total <= 0) return -1;
    int64_t roll = randi_range(r, 0, total - 1);
    for (int i = 0; i < ngroups; i++) { roll -= groups[i].weight > 0 ? groups[i].weight : 0; if (roll < 0) return i; }
    return -1;
}
static int weighted_enemy(Rng *r, const Group *g) {
    int total = 0;
    for (int i = 0; i < g->n; i++) total += g->eweight[i] > 0 ? g->eweight[i] : 0;
    if (total <= 0) return -1;
    int64_t roll = randi_range(r, 0, total - 1);
    for (int i = 0; i < g->n; i++) { roll -= g->eweight[i] > 0 ? g->eweight[i] : 0; if (roll < 0) return g->enemy[i]; }
    return -1;
}

/* Returns 0 on success, -1 where roll() would return an empty troop. */
static int roll(Rng *r, Troop *troop) {
    int gi = weighted_group(r);
    if (gi < 0) return -1;
    const Group *g = &groups[gi];
    if (g->invalid) return -1;
    int maximum = 0;
    for (int i = 0; i < g->n; i++) { int e = find_enemy(g->enemy[i]); if (e < 0 || enemies[e].t < 0) return -1; maximum += enemies[e].max_count; }
    int cap = max_enemies < 1 ? 1 : (max_enemies > 10 ? 10 : max_enemies);
    if (maximum > cap) maximum = cap;
    if (maximum <= 0) return -1;
    int count = (int)randi_range(r, 1, maximum);
    int ids[16], n = 0, big = 0;
    for (int attempt = 0; attempt < 100; attempt++) {
        if (n >= count) break;
        int id = weighted_enemy(r, g);
        int e = find_enemy(id);
        if (e < 0) return -1;
        int multiplicity = 0, have = 0;
        for (int i = 0; i < g->n; i++) if (g->enemy[i] == id) multiplicity++;
        for (int i = 0; i < n; i++) if (ids[i] == id) have++;
        if (have >= enemies[e].max_count * multiplicity) continue;
        if (templates[enemies[e].t].size == 1) {
            if (big >= 5) { count--; continue; }
            if (n > 4) {
                int swap = -1;
                for (int i = 0; i < 5; i++) if (templates[enemies[find_enemy(ids[i])].t].size == 0) { swap = i; break; }
                if (swap < 0) continue;
                ids[n++] = ids[swap]; ids[swap] = id;
            } else ids[n++] = id;
            big++;
        } else ids[n++] = id;
    }
    troop->count = n;
    for (int k = 0; k < n; k++) {
        Actor *a = &troop->a[k];
        const Enemy *e = &enemies[find_enemy(ids[k])];
        const Template *t = &templates[e->t];
        a->enemy = e->id; a->can_capture = e->pet_flag != 0;
        a->level = (int)randi_range(r, e->level_min, e->level_max);
        int initial[4];
        for (int i = 0; i < 4; i++) { a->weights[i] = t->w[i] + (int)randi_range(r, -2, 2); initial[i] = a->weights[i]; }
        for (int i = 0; i < 10; i++) initial[randi_range(r, 0, 3)]++;
        a->growth_seed = rng_next(r);
        /* actor() generates enabled original drops before the next actor. */
        for (int i = 0; i < e->drop_draws; i++) (void)randi_range(r, 0, 999);
        for (int i = 0; i < 4; i++) a->base[i] = (int64_t)initial[i] * (t->initial + (int64_t)(a->level - 1) * t->wild_growth);
    }
    return 0;
}

/* Progression.project_pet(actor, 120) then derived(): attack, defence, speed, max_hp. */
static void project(const Actor *a, const Template *t, int out[4]) {
    int64_t base[4] = {a->base[0], a->base[1], a->base[2], a->base[3]};
    int low = 450 + t->rank * 20;
    for (int level = a->level + 1; level <= 120; level++) {
        Rng r; rng_seed(&r, (uint64_t)((int64_t)a->growth_seed + (int64_t)level * 104729));
        int extra[4] = {0, 0, 0, 0};
        for (int i = 0; i < 10; i++) extra[randi_range(&r, 0, 3)]++;
        int64_t roll = randi_range(&r, low, low + 50);
        for (int i = 0; i < 4; i++) base[i] += (int64_t)(a->weights[i] + extra[i]) * roll / 100;
    }
    int64_t v = base[0], s = base[1], tg = base[2], d = base[3];
    int64_t attack = (20 * s + 2 * tg + 2 * v + d) / 2000, defence = (20 * tg + 2 * s + 2 * v + d) / 2000, speed = d / 100;
    int64_t hp = (4 * v + s + tg + d) / 100;
    out[0] = (int)(attack < 1 ? 1 : attack); out[1] = (int)(defence < 0 ? 0 : defence); out[2] = (int)(speed < 1 ? 1 : speed);
    out[3] = (int)(hp < 1 ? 1 : hp);
}

/* ---- survey pool ---------------------------------------------------------- */
static const SurveyRule *survey_for(int template_id) {
    for (int i = 0; i < nsurvey; i++) if (survey_rules[i].template_id == template_id) return &survey_rules[i];
    return NULL;
}
static const SurveyRule *sort_rule; static int sort_stat;
static int64_t cand_id(const Candidate *c) { return c->index * 16 + c->slot; }
/* keep_rule.gd `better`: the rule's full order descending, then the earlier roll. */
static int better_cmp(const Candidate *a, const Candidate *b) {
    for (int k = 0; k < sort_rule->norder; k++) {
        int key = sort_rule->order[k];
        if (a->st[key] != b->st[key]) return a->st[key] > b->st[key] ? -1 : 1;
    }
    int64_t ia = cand_id(a), ib = cand_id(b);
    return ia < ib ? -1 : (ia > ib);
}
static int tier_cmp(const void *x, const void *y) {
    const Candidate *a = x, *b = y;
    if (a->st[0] != b->st[0]) return a->st[0] > b->st[0] ? -1 : 1;
    return better_cmp(a, b);
}
/* Champions of one stat: that stat, then 三围合, then `better`. */
static int champion_cmp(const void *x, const void *y) {
    const Candidate *a = x, *b = y;
    if (a->st[sort_stat] != b->st[sort_stat]) return a->st[sort_stat] > b->st[sort_stat] ? -1 : 1;
    if (a->st[0] != b->st[0]) return a->st[0] > b->st[0] ? -1 : 1;
    return better_cmp(a, b);
}
/* Drops every candidate the keep rule would release. Caller holds pool_lock. */
static void pool_prune(void) {
    Candidate *kept = calloc(pool_size + 1, sizeof *kept), *group = calloc(pool_size + 1, sizeof *group);
    char *mark = calloc(pool_size + 1, 1);
    int nkept = 0;
    for (int r = 0; r < nsurvey; r++) {
        const SurveyRule *rule = &survey_rules[r];
        int n = 0;
        for (int i = 0; i < pool_size; i++) if (pool[i].template_id == rule->template_id) group[n++] = pool[i];
        memset(mark, 0, n);
        sort_rule = rule;
        qsort(group, n, sizeof *group, tier_cmp);
        int tiers = 0, place = 0;
        for (int i = 0; i < n; i++) {
            if (i == 0 || group[i].st[0] != group[i - 1].st[0]) { tiers++; place = 0; }
            if (tiers > rule->tiers) break;
            if (place++ < rule->per_tier) mark[i] = 1;
        }
        Candidate *keep_now = calloc(n + 1, sizeof *keep_now); int nk = 0;
        for (int i = 0; i < n; i++) if (mark[i]) keep_now[nk++] = group[i];
        for (int stat = 1; stat <= 4 && rule->champions > 0; stat++) {
            if (!rule->champion[stat - 1]) continue;
            sort_stat = stat;
            qsort(group, n, sizeof *group, champion_cmp);
            for (int i = 0; i < n && i < rule->champions; i++) {
                int have = 0;
                for (int j = 0; j < nk; j++) if (keep_now[j].index == group[i].index && keep_now[j].slot == group[i].slot) have = 1;
                if (!have) keep_now[nk++] = group[i];
            }
        }
        for (int i = 0; i < nk; i++) kept[nkept++] = keep_now[i];
        free(keep_now);
    }
    memcpy(pool, kept, nkept * sizeof *pool);
    pool_size = nkept;
    free(kept); free(group); free(mark);
}
static void pool_add(int64_t index, int slot, int template_id, const int st[4]) {
    pthread_mutex_lock(&pool_lock);
    if (pool_size >= pool_capacity) {
        pool_prune();
        if (pool_size * 2 >= pool_capacity) {
            pool_capacity = pool_capacity ? pool_capacity * 2 : 256;
            pool = realloc(pool, pool_capacity * sizeof *pool);
        }
    }
    Candidate *c = &pool[pool_size++];
    c->index = index; c->slot = slot; c->template_id = template_id;
    c->st[0] = st[0] + st[1] + st[2]; c->st[1] = st[0]; c->st[2] = st[1]; c->st[3] = st[2]; c->st[4] = st[3];
    pthread_mutex_unlock(&pool_lock);
}

static const StatFilter *stat_for(int template_id) {
    for (int i = 0; i < nstat; i++) if (stat_template[i] == template_id) return &stat_filters[i];
    return NULL;
}
static int evaluate(const StatFilter *s, const int st[4]) {
    int any = 0, all = 1, count = 0;
    double values[4] = {st[0] + st[1] + st[2], st[0], st[1], st[2]};
    for (int m = 0; m < 4; m++) {
        if (!s->on[m]) continue;
        count++;
        int passes = s->strict[m] ? values[m] > s->value[m] : values[m] >= s->value[m];
        any = any || passes; all = all && passes;
    }
    return count == 0 || (s->any ? any : all);
}

static int is_usable(int template_id) { for (int i = 0; i < nusable; i++) if (usable[i] == template_id) return 1; return 0; }

/* scan_once for roll `index`: the hit slot, -1 for no hit, -2 for an empty troop. */
static int scan(uint64_t index, Tally *tally) {
    Rng r; rng_seed(&r, roll_seed(run_seed, index));
    Troop troop;
    if (roll(&r, &troop) < 0) return -2;
    for (int i = 0; i < troop.count; i++) {
        const Actor *a = &troop.a[i];
        if (!a->can_capture) continue;
        const Enemy *e = &enemies[find_enemy(a->enemy)];
        const Template *t = &templates[e->t];
        if (!is_usable(t->id)) continue;
        if (f_template >= 0 && t->id != f_template) continue;
        if (f_level_one && a->level != 1) continue;
        tally->inspected++;
        int offsets[4], total = 0;
        for (int k = 0; k < 4; k++) { offsets[k] = a->weights[k] - t->w[k]; total += offsets[k]; }
        if (total > tally->best) tally->best = total;
        if (total < f_total) continue;
        int ok = 1;
        if (f_has_offsets) for (int k = 0; k < 4; k++) if (offsets[k] < f_offsets[k]) ok = 0;
        if (!ok) continue;
        if (flow && survey_for(t->id)) {
            /* 摸底: a candidate, not a hit; the scan goes on. */
            int st[4]; project(a, t, st);
            int sum = st[0] + st[1] + st[2];
            if (sum > tally->best_sum || (sum == tally->best_sum && st[0] > tally->best_attack)) { tally->best_sum = sum; tally->best_attack = st[0]; }
            pool_add((int64_t)index, i, t->id, st);
            continue;
        }
        if (flow) {
            const StatFilter *s = stat_for(t->id);
            if (s && s->enabled) {
                int st[4]; project(a, t, st);
                int sum = st[0] + st[1] + st[2];
                if (sum > tally->best_sum || (sum == tally->best_sum && st[0] > tally->best_attack)) { tally->best_sum = sum; tally->best_attack = st[0]; }
                if (!evaluate(s, st)) { tally->pred_rejects++; continue; }
            }
        }
        return i;
    }
    return -1;
}

/* ---- parallel scan with ordered commit ------------------------------------ */
#define CHUNK 65536
typedef struct { int done; int result; int64_t at; Tally tally; } Chunk;
static Chunk *ring; static int ring_size;
static int64_t next_chunk, committed_chunk, stop_all;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t changed = PTHREAD_COND_INITIALIZER;

static void *worker(void *unused) {
    (void)unused;
    for (;;) {
        pthread_mutex_lock(&lock);
        while (!stop_all && next_chunk >= committed_chunk + ring_size) pthread_cond_wait(&changed, &lock);
        if (stop_all) { pthread_mutex_unlock(&lock); return NULL; }
        int64_t c = next_chunk++;
        pthread_mutex_unlock(&lock);
        Tally t = {0, 0, -9, -1, -1};
        int result = -1; int64_t at = 0;
        int64_t from = start_index + c * CHUNK, to = from + CHUNK;
        if (limit_index > 0 && to > limit_index) to = limit_index;
        int64_t i;
        for (i = from; i < to; i++) {
            Tally before = t;
            int slot = scan((uint64_t)i, &t);
            if (slot != -1) { t = before; result = slot; at = i; break; }
        }
        if (result == -1) at = to;
        pthread_mutex_lock(&lock);
        Chunk *k = &ring[c % ring_size];
        k->done = 1; k->result = result; k->at = at; k->tally = t;
        pthread_cond_broadcast(&changed);
        pthread_mutex_unlock(&lock);
    }
}

static void merge(Tally *into, const Tally *t) {
    into->inspected += t->inspected; into->pred_rejects += t->pred_rejects;
    if (t->best > into->best) into->best = t->best;
    if (t->best_sum > into->best_sum || (t->best_sum == into->best_sum && t->best_attack > into->best_attack)) { into->best_sum = t->best_sum; into->best_attack = t->best_attack; }
}

static const char *status_path;
static void write_status(const char *kind, int64_t index, int slot, const Tally *t) {
    char tmp[4096];
    snprintf(tmp, sizeof tmp, "%s.tmp", status_path);
    FILE *f = open_file(tmp, "wb");
    if (!f) return;
    fprintf(f, "%s %lld %d %llu %d %llu %d %d\n", kind, (long long)index, slot, (unsigned long long)t->inspected, t->best, (unsigned long long)t->pred_rejects, t->best_sum, t->best_attack);
    if (nsurvey > 0) {
        pthread_mutex_lock(&pool_lock);
        pool_prune();
        for (int i = 0; i < pool_size; i++) {
            const Candidate *c = &pool[i];
            fprintf(f, "cand %lld %d %d %d %d %d %d %d\n", (long long)c->index, c->slot, c->template_id, c->st[0], c->st[1], c->st[2], c->st[3], c->st[4]);
        }
        pthread_mutex_unlock(&pool_lock);
    }
    fclose(f);
    replace_file(tmp, status_path);
}

static double now(void) { struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts); return ts.tv_sec + ts.tv_nsec / 1e9; }

static int print_roll(int64_t index) {
    Rng r; rng_seed(&r, roll_seed(run_seed, (uint64_t)index));
    Troop troop;
    printf("roll %lld seed %lld", (long long)index, (long long)roll_seed(run_seed, (uint64_t)index));
    if (roll(&r, &troop) < 0) { printf(" empty\nscan -2\n"); return 0; }
    printf(" count %d\n", troop.count);
    for (int i = 0; i < troop.count; i++) {
        const Actor *a = &troop.a[i];
        const Template *t = &templates[enemies[find_enemy(a->enemy)].t];
        int st[4]; project(a, t, st);
        printf("enemy %d level %d weights %d %d %d %d seed %u base %lld %lld %lld %lld lv120 %d %d %d hp %d\n", a->enemy, a->level,
               a->weights[0], a->weights[1], a->weights[2], a->weights[3], a->growth_seed,
               (long long)a->base[0], (long long)a->base[1], (long long)a->base[2], (long long)a->base[3], st[0], st[1], st[2], st[3]);
    }
    Tally t = {0, 0, -9, -1, -1};
    printf("scan %d\n", scan((uint64_t)index, &t));
    return 0;
}

int main(int argc, char **argv) {
#ifdef _WIN32
    argv = utf8_arguments(&argc);
    _setmode(_fileno(stdout), _O_BINARY);  /* LF, as on Unix: the tests parse --roll output */
#endif
    if (argc < 3) { fprintf(stderr, "usage: fast_hunt INPUT STATUS | fast_hunt INPUT --roll FROM [COUNT]\n"); return 2; }
    load(argv[1]);
    if (!strcmp(argv[2], "--roll")) {
        int64_t from = argc > 3 ? atoll(argv[3]) : 0, count = argc > 4 ? atoll(argv[4]) : 1;
        for (int64_t i = from; i < from + count; i++) print_roll(i);
        return 0;
    }
    status_path = argv[2];
    int cores = cpu_count();
    if (threads <= 0) threads = cores > 2 ? cores - 1 : 1;
    ring_size = threads * 4;
    ring = calloc(ring_size, sizeof *ring);
    pthread_t *pool = calloc(threads, sizeof *pool);
    for (int i = 0; i < threads; i++) pthread_create(&pool[i], NULL, worker, NULL);
    Tally total = {0, 0, -9, -1, -1};
    int64_t next = start_index;
    double last = 0;
    const char *kind = NULL; int64_t index = 0; int slot = -1;
    /* The backend kills this process when the hunt stops; if the backend
     * itself goes away, stop too rather than scan without an owner. */
    watch_parent();
    pthread_mutex_lock(&lock);
    while (!kind) {
        Chunk *k = &ring[committed_chunk % ring_size];
        if (k->done) {
            merge(&total, &k->tally);
            if (k->result >= 0) { kind = "hit"; index = k->at; slot = k->result; }
            else if (k->result == -2) { kind = "stop"; index = k->at; }
            else {
                next = k->at;
                if (limit_index > 0 && next >= limit_index) { kind = "limit"; index = next; }
            }
            k->done = 0; committed_chunk++;
            pthread_cond_broadcast(&changed);
            if (kind || now() - last <= 0.1) continue;
        }
        if (now() - last > 0.1) {
            if (parent_gone()) { kind = "orphaned"; break; }
            pthread_mutex_unlock(&lock);
            write_status("progress", next, 0, &total);
            last = now();
            pthread_mutex_lock(&lock);
        }
        if (ring[committed_chunk % ring_size].done) continue;
        struct timespec wake; clock_gettime(CLOCK_REALTIME, &wake);
        wake.tv_nsec += 20000000; if (wake.tv_nsec >= 1000000000) { wake.tv_sec++; wake.tv_nsec -= 1000000000; }
        pthread_cond_timedwait(&changed, &lock, &wake);
    }
    stop_all = 1;
    pthread_cond_broadcast(&changed);
    pthread_mutex_unlock(&lock);
    for (int i = 0; i < threads; i++) pthread_join(pool[i], NULL);
    if (strcmp(kind, "orphaned")) write_status(kind, index, slot, &total);
    return 0;
}
