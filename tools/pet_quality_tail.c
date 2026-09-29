/* Lv120 stat-sum tail of full-grade blue dragons (docs/game-systems/pet-quality.md).
 *
 * Same rules as client/server/progression.gd: template 92 (initial 29,
 * weights 27/36/16/20), all four grades +2, caught at Lv1 (base = points * 29),
 * then grow_pet for levels 2..120 (10 random points, roll 470..520 for
 * growth rank 1, integer arithmetic), derived() for attack/defence/speed.
 * The random generator differs from Godot's, the distribution does not.
 *
 *   cc -O2 -o build/pet_quality_tail tools/pet_quality_tail.c
 *   build/pet_quality_tail 400000000 14      # pets, processes
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>

#define MAXSUM 700
#define MAXATK 320

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

typedef struct { uint64_t n, sum_total, atk_total; uint64_t by_sum[MAXSUM]; uint64_t by_sum_atk292[MAXSUM]; uint64_t by_atk[MAXATK]; } Tally;

static void run(uint64_t pets, uint64_t seed_value, Tally *t) {
    const int w[4] = {29, 38, 18, 22}; /* 27/36/16/20 + 2 */
    seed(seed_value);
    for (uint64_t k = 0; k < pets; k++) {
        int64_t base[4], ini[4] = {w[0], w[1], w[2], w[3]};
        for (int i = 0; i < 10; i++) ini[below(4)]++;
        for (int i = 0; i < 4; i++) base[i] = ini[i] * 29;
        for (int level = 2; level <= 120; level++) {
            int extra[4] = {0, 0, 0, 0};
            for (int i = 0; i < 10; i++) extra[below(4)]++;
            int64_t roll = 470 + below(51);
            for (int i = 0; i < 4; i++) base[i] += (w[i] + extra[i]) * roll / 100;
        }
        int64_t v = base[0], st = base[1], tg = base[2], dx = base[3];
        int atk = (int)((20 * st + 2 * tg + 2 * v + dx) / 2000), def = (int)((20 * tg + 2 * st + 2 * v + dx) / 2000), spd = (int)(dx / 100);
        int sum = atk + def + spd;
        t->n++; t->sum_total += sum; t->atk_total += atk;
        if (sum < MAXSUM) { t->by_sum[sum]++; if (atk >= 292) t->by_sum_atk292[sum]++; }
        if (atk < MAXATK) t->by_atk[atk]++;
    }
}

static uint64_t at_least(const uint64_t *h, int from, int size) { uint64_t c = 0; for (int i = from; i < size; i++) c += h[i]; return c; }
static int percentile(const uint64_t *h, int size, uint64_t n, double top) {
    uint64_t want = (uint64_t)(n * top), c = 0;
    for (int i = size - 1; i >= 0; i--) { c += h[i]; if (c > want) return i; }
    return 0;
}

int main(int argc, char **argv) {
    uint64_t pets = argc > 1 ? strtoull(argv[1], 0, 10) : 10000000ULL;
    int jobs = argc > 2 ? atoi(argv[2]) : 8;
    int fds[64][2];
    for (int j = 0; j < jobs; j++) {
        pipe(fds[j]);
        if (fork() == 0) {
            Tally *t = calloc(1, sizeof *t);
            run(pets / jobs + (j < (int)(pets % jobs)), 0x5EED0000ULL + j, t);
            write(fds[j][1], t, sizeof *t); _exit(0);
        }
    }
    Tally *all = calloc(1, sizeof *all), *part = calloc(1, sizeof *part);
    for (int j = 0; j < jobs; j++) {
        size_t got = 0; while (got < sizeof *part) { ssize_t r = read(fds[j][0], (char *)part + got, sizeof *part - got); if (r <= 0) break; got += r; }
        all->n += part->n; all->sum_total += part->sum_total; all->atk_total += part->atk_total;
        for (int i = 0; i < MAXSUM; i++) { all->by_sum[i] += part->by_sum[i]; all->by_sum_atk292[i] += part->by_sum_atk292[i]; }
        for (int i = 0; i < MAXATK; i++) all->by_atk[i] += part->by_atk[i];
    }
    while (wait(0) > 0) {}
    uint64_t n = all->n; int max = 0; for (int i = 0; i < MAXSUM; i++) if (all->by_sum[i]) max = i;
    printf("pets %llu\nmean sum %.3f  mean attack %.3f\n", (unsigned long long)n, (double)all->sum_total / n, (double)all->atk_total / n);
    printf("sum median %d  top10%% %d  top1%% %d  top0.1%% %d  max %d\n", percentile(all->by_sum, MAXSUM, n, 0.5), percentile(all->by_sum, MAXSUM, n, 0.1), percentile(all->by_sum, MAXSUM, n, 0.01), percentile(all->by_sum, MAXSUM, n, 0.001), max);
    printf("attack top1%% %d  top0.1%% %d\n", percentile(all->by_atk, MAXATK, n, 0.01), percentile(all->by_atk, MAXATK, n, 0.001));
    for (int v = 620; v <= 623; v++) printf(">=%d %.4f%%\n", v, 100.0 * at_least(all->by_sum, v, MAXSUM) / n);
    const char *names[] = {">=623 and attack>=292", ">=624", ">=624 and attack>=292", ">=625", ">=626"};
    uint64_t counts[] = {at_least(all->by_sum_atk292, 623, MAXSUM), at_least(all->by_sum, 624, MAXSUM), at_least(all->by_sum_atk292, 624, MAXSUM), at_least(all->by_sum, 625, MAXSUM), at_least(all->by_sum, 626, MAXSUM)};
    for (int i = 0; i < 5; i++) printf("%-24s %llu  1 in %.0f\n", names[i], (unsigned long long)counts[i], counts[i] ? (double)n / counts[i] : 0.0);
    return 0;
}
