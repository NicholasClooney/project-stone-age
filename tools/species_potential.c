/* Lv120 potential of every pet species for 宠物大全 (docs/technical/species-potential.md).
 *
 * Generalizes tools/pet_quality_tail.c. Same integer rules as
 * client/server/progression.gd and encounter_catalog.gd: a full-grade pet
 * (all four growth weights +2) caught at level L has base stat
 * points * (initial + (L-1) * wild_growth), where points are the weights plus
 * 10 randomly placed points; grow_pet then adds (weight + extra) * roll / 100
 * per level up to 120 (10 random points, roll low..low+50 with
 * low = 450 + 20 * growth rank, rank from the template's weight sum), and
 * derived() gives max_hp, attack, defence and speed. The random generator
 * differs from Godot's; the distribution does not.
 *
 * Input (stdin), one species per line:
 *   template_id initial wild_growth w0 w1 w2 w3 wild_level
 * wild_level is the lowest level the species is caught at in the wild, or 0
 * when there is no second basis to simulate (no wild catch, or Lv1).
 * Output (stdout), one line per species and basis:
 *   template_id basis level pets mean_sum mean_attack mean_defence mean_speed
 *   mean_hp median top10 top1 top01 max top1_attack top01_attack
 * basis is "lv1" or "wild". Every species and basis is split into CHUNKS
 * chunks with fixed seeds, so the result does not depend on the process count.
 *
 *   cc -O2 -o build/species_potential tools/species_potential.c
 *   build/species_potential 1000000 14 < species.txt   # pets per basis, processes
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>

#define MAXSUM 2048
#define MAXATK 1024
#define CHUNKS 16
#define MAXSPECIES 1200

typedef struct { int id, initial, growth, w[4], wild; } Species;
typedef struct { uint64_t n, sum, atk, def, spd, hp; uint32_t by_sum[MAXSUM]; uint32_t by_atk[MAXATK]; } Tally;

static uint64_t s[4];
static inline uint64_t rotl(uint64_t x, int k) { return (x << k) | (x >> (64 - k)); }
static inline uint64_t next(void) { /* xoshiro256** */
    uint64_t r = rotl(s[1] * 5, 7) * 9, t = s[1] << 17;
    s[2] ^= s[0]; s[3] ^= s[1]; s[1] ^= s[2]; s[0] ^= s[3]; s[2] ^= t; s[3] = rotl(s[3], 45);
    return r;
}
static inline uint32_t below(uint32_t n) { /* unbiased 0..n-1 */
    uint32_t limit = (uint32_t)(-n) % n, x;
    do x = (uint32_t)(next() >> 32); while (x < limit);
    return x % n;
}
static void seed(uint64_t v) {
    for (int i = 0; i < 4; i++) { v += 0x9E3779B97F4A7C15ULL; uint64_t z = v;
        z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL; z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL; s[i] = z ^ (z >> 31); }
}

static int rank_of(const Species *sp) {
    int total = sp->w[0] + sp->w[1] + sp->w[2] + sp->w[3];
    const int limits[6] = {100, 95, 90, 85, 80, 0};
    for (int i = 0; i < 6; i++) if (total >= limits[i]) return i;
    return 5;
}

static void run(const Species *sp, int level, uint64_t pets, uint64_t seed_value, Tally *t) {
    int w[4];
    for (int i = 0; i < 4; i++) w[i] = sp->w[i] + 2;
    int64_t low = 450 + rank_of(sp) * 20, factor = sp->initial + (int64_t)(level - 1) * sp->growth;
    seed(seed_value);
    for (uint64_t k = 0; k < pets; k++) {
        int64_t base[4], ini[4] = {w[0], w[1], w[2], w[3]};
        for (int i = 0; i < 10; i++) ini[below(4)]++;
        for (int i = 0; i < 4; i++) base[i] = ini[i] * factor;
        for (int lv = level + 1; lv <= 120; lv++) {
            int extra[4] = {0, 0, 0, 0};
            for (int i = 0; i < 10; i++) extra[below(4)]++;
            int64_t roll = low + below(51);
            for (int i = 0; i < 4; i++) base[i] += (w[i] + extra[i]) * roll / 100;
        }
        int64_t v = base[0], st = base[1], tg = base[2], dx = base[3];
        int hp = (int)((4 * v + st + tg + dx) / 100), atk = (int)((20 * st + 2 * tg + 2 * v + dx) / 2000);
        int def = (int)((20 * tg + 2 * st + 2 * v + dx) / 2000), spd = (int)(dx / 100);
        if (hp < 1) hp = 1; if (atk < 1) atk = 1; if (def < 0) def = 0; if (spd < 1) spd = 1;
        int sum = atk + def + spd;
        t->n++; t->sum += sum; t->atk += atk; t->def += def; t->spd += spd; t->hp += hp;
        t->by_sum[sum < MAXSUM ? sum : MAXSUM - 1]++;
        t->by_atk[atk < MAXATK ? atk : MAXATK - 1]++;
    }
}

static int percentile(const uint32_t *h, int size, uint64_t n, double top) {
    uint64_t want = (uint64_t)(n * top), c = 0;
    for (int i = size - 1; i >= 0; i--) { c += h[i]; if (c > want) return i; }
    return 0;
}

static Species species[MAXSPECIES];

int main(int argc, char **argv) {
    uint64_t pets = argc > 1 ? strtoull(argv[1], 0, 10) : 1000000ULL;
    int jobs = argc > 2 ? atoi(argv[2]) : 8;
    if (jobs < 1) jobs = 1; if (jobs > 64) jobs = 64;
    int count = 0;
    while (count < MAXSPECIES) {
        Species *sp = &species[count];
        if (scanf("%d %d %d %d %d %d %d %d", &sp->id, &sp->initial, &sp->growth, &sp->w[0], &sp->w[1], &sp->w[2], &sp->w[3], &sp->wild) != 8) break;
        count++;
    }
    /* Unit u = (species, basis, chunk); process j runs every unit with u % jobs == j. */
    int units = count * 2 * CHUNKS;
    size_t bytes = sizeof(Tally) * (size_t)count * 2;
    int fds[64][2];
    for (int j = 0; j < jobs; j++) {
        if (pipe(fds[j]) != 0) { perror("pipe"); return 1; }
        if (fork() == 0) {
            Tally *t = calloc((size_t)count * 2, sizeof(Tally));
            for (int u = j; u < units; u += jobs) {
                int index = u / (2 * CHUNKS), basis = (u / CHUNKS) % 2, chunk = u % CHUNKS;
                const Species *sp = &species[index];
                if (basis == 1 && sp->wild <= 1) continue;
                uint64_t share = pets / CHUNKS + ((uint64_t)chunk < pets % CHUNKS);
                run(sp, basis == 1 ? sp->wild : 1, share, 0x5EED000000ULL ^ ((uint64_t)sp->id << 16) ^ ((uint64_t)basis << 8) ^ (uint64_t)chunk, &t[index * 2 + basis]);
            }
            size_t sent = 0;
            while (sent < bytes) { ssize_t w = write(fds[j][1], (char *)t + sent, bytes - sent); if (w <= 0) _exit(1); sent += w; }
            _exit(0);
        }
        close(fds[j][1]);
    }
    Tally *all = calloc((size_t)count * 2, sizeof(Tally)), *part = malloc(bytes);
    for (int j = 0; j < jobs; j++) {
        size_t got = 0;
        while (got < bytes) { ssize_t r = read(fds[j][0], (char *)part + got, bytes - got); if (r <= 0) break; got += r; }
        if (got != bytes) { fprintf(stderr, "worker %d failed\n", j); return 1; }
        for (int k = 0; k < count * 2; k++) {
            Tally *a = &all[k], *p = &part[k];
            a->n += p->n; a->sum += p->sum; a->atk += p->atk; a->def += p->def; a->spd += p->spd; a->hp += p->hp;
            for (int i = 0; i < MAXSUM; i++) a->by_sum[i] += p->by_sum[i];
            for (int i = 0; i < MAXATK; i++) a->by_atk[i] += p->by_atk[i];
        }
    }
    while (wait(0) > 0) {}
    for (int k = 0; k < count * 2; k++) {
        Tally *a = &all[k];
        if (!a->n) continue;
        const Species *sp = &species[k / 2];
        int max = 0; for (int i = 0; i < MAXSUM; i++) if (a->by_sum[i]) max = i;
        double n = (double)a->n;
        printf("%d %s %d %llu %.3f %.3f %.3f %.3f %.3f %d %d %d %d %d %d %d\n", sp->id, k % 2 ? "wild" : "lv1", k % 2 ? sp->wild : 1,
               (unsigned long long)a->n, a->sum / n, a->atk / n, a->def / n, a->spd / n, a->hp / n,
               percentile(a->by_sum, MAXSUM, a->n, 0.5), percentile(a->by_sum, MAXSUM, a->n, 0.1),
               percentile(a->by_sum, MAXSUM, a->n, 0.01), percentile(a->by_sum, MAXSUM, a->n, 0.001), max,
               percentile(a->by_atk, MAXATK, a->n, 0.01), percentile(a->by_atk, MAXATK, a->n, 0.001));
    }
    return 0;
}
