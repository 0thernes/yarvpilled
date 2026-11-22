/*
 * Differential fuzzer for the world-loop kernels (libFuzzer + ASan + UBSan).
 *
 * Each input decodes into a small random world (size, cell sizes, creatures,
 * positions, headings, ages, energies, ANY int32 costs and actions, food,
 * fertility) plus 1-6 ticks of actions. The same world is stepped by
 *   C kernel (kernel_c.c), asm backend (C + crowd_x86_64.S), Rust kernel,
 * and after every sense and every act all three must agree bit for bit
 * (sensor outputs, births/deaths lists, every array, every counter).
 * Any disagreement, crash, out-of-bounds access or UB aborts the run.
 *
 * Build + run: fuzz/run.sh [seconds]
 */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "../ext/yarvpilled_native/world.h"
#include "../ext/yarvpilled_native/trig_table.h"

typedef struct { const uint8_t *p; size_t n; } Rd;
static uint32_t rd8(Rd *r) { if (!r->n) return 0; r->n--; return *r->p++; }
static uint32_t rd16(Rd *r) { return rd8(r) | rd8(r) << 8; }
static uint32_t rd32(Rd *r) { return rd16(r) | rd16(r) << 16; }

#define ALLOC(f, n) (w->f = calloc((size_t)(n) ? (size_t)(n) : 1, sizeof *w->f))
static void wmake(World *w, int cap, double ww, double hh, int fcell) {
  memset(w, 0, sizeof *w);
  w->cap = cap; w->w = ww; w->h = hh; w->fcell = fcell;
  w->fw = (int)(ww / fcell); w->fh = (int)(hh / fcell);
  w->gcell = 24; w->gw = (int)((ww + 23.999999) / 24); w->gh = (int)((hh + 23.999999) / 24);
  if (w->gw < 1) w->gw = 1;
  if (w->gh < 1) w->gh = 1;
  ALLOC(x, cap); ALLOC(y, cap); ALLOC(heading, cap); ALLOC(age, cap); ALLOC(species, cap);
  ALLOC(cost, cap); ALLOC(last_action, cap); ALLOC(energy, cap); ALLOC(alive, cap);
  int nf = w->fw * w->fh;
  ALLOC(food, nf); ALLOC(fert, nf); ALLOC(facc, nf);
  ALLOC(ghead, w->gw * w->gh); ALLOC(gnext, cap);
  ALLOC(sbuf, (long)cap * SENSORS); ALLOC(abuf, cap); ALLOC(bbuf, cap); ALLOC(dbuf, cap);
}
static void wfree(World *w) {
  free(w->x); free(w->y); free(w->heading); free(w->age); free(w->species); free(w->cost);
  free(w->last_action); free(w->energy); free(w->alive); free(w->food); free(w->fert); free(w->facc);
  free(w->ghead); free(w->gnext); free(w->sbuf); free(w->abuf); free(w->bbuf); free(w->dbuf);
}
#define CP(f, n) memcpy(d->f, s->f, (size_t)(n) * sizeof *s->f)
static void wcopy(World *d, const World *s) {
  wmake(d, s->cap, s->w, s->h, s->fcell);
  d->used = s->used;
  CP(x, s->cap); CP(y, s->cap); CP(heading, s->cap); CP(age, s->cap); CP(species, s->cap);
  CP(cost, s->cap); CP(last_action, s->cap); CP(energy, s->cap); CP(alive, s->cap);
  int nf = s->fw * s->fh;
  CP(food, nf); CP(fert, nf); CP(facc, nf);
}
#define EQ(f, n) (memcmp(a->f, b->f, (size_t)(n) * sizeof *a->f) == 0)
static int weq(const World *a, const World *b) {
  int nf = a->fw * a->fh;
  return a->used == b->used && a->eaten_total == b->eaten_total && a->ticks == b->ticks &&
         a->deaths_total == b->deaths_total && EQ(x, a->cap) && EQ(y, a->cap) && EQ(heading, a->cap) &&
         EQ(age, a->cap) && EQ(cost, a->cap) && EQ(last_action, a->cap) && EQ(energy, a->cap) &&
         EQ(alive, a->cap) && EQ(food, nf) && EQ(facc, nf);
}

int LLVMFuzzerInitialize(int *argc, char ***argv) {
  (void)argc; (void)argv;
  memcpy(yp_cos_t, YP_COS_BITS, sizeof yp_cos_t);
  memcpy(yp_sin_t, YP_SIN_BITS, sizeof yp_sin_t);
  return 0;
}

#include <stdio.h>
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "kernel_fuzz: check failed at line %d: %s\n", __LINE__, #c); __builtin_trap(); } } while (0)

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  Rd r = { data, size };
  int cap = 1 + (int)(rd8(&r) % 48);
  int fcell = 1 + (int)(rd8(&r) % 16);
  /* Precondition enforced by World.new: w, h >= 72 (at least 3 grid cells of 24). */
  int fmin = (72 + fcell - 1) / fcell;
  int fw = fmin + (int)(rd8(&r) % 12), fh = fmin + (int)(rd8(&r) % 12);
  double ww = fw * fcell + (double)(rd8(&r) % fcell), hh = fh * fcell + (double)(rd8(&r) % fcell);
  World base;
  wmake(&base, cap, ww, hh, fcell);
  base.used = 1 + (int)(rd8(&r) % cap);
  for (int i = 0; i < base.used; i++) {
    base.x[i] = rd16(&r) / 65536.0 * ww;
    base.y[i] = rd16(&r) / 65536.0 * hh;
    base.heading[i] = (int32_t)(rd8(&r) & 63);
    base.age[i] = (int32_t)(rd16(&r) % MAX_AGE);
    base.energy[i] = (int64_t)(int32_t)rd32(&r);
    base.cost[i] = (int32_t)rd32(&r);            /* any int32, including INT_MIN/INT_MAX */
    base.alive[i] = (rd8(&r) % 8) != 0;
    base.species[i] = i;
  }
  for (int c = 0; c < base.fw * base.fh; c++) {
    base.food[c] = (uint8_t)rd8(&r); base.fert[c] = (uint8_t)rd8(&r); base.facc[c] = (uint8_t)rd8(&r);
  }
  int64_t thresh = (int64_t)(int32_t)rd32(&r);
  int ticks = 1 + (int)(rd8(&r) % 6);

  World wc, wa, wr;
  wcopy(&wc, &base); wcopy(&wa, &base); wcopy(&wr, &base);
  wc.backend = BACKEND_C; wa.backend = BACKEND_ASM; wr.backend = BACKEND_RUST;
  int32_t *act = calloc((size_t)cap, sizeof *act);
  int32_t *so[3], *bi[3], *de[3];
  for (int k = 0; k < 3; k++) {
    so[k] = calloc((size_t)cap * SENSORS, sizeof(int32_t));
    bi[k] = calloc((size_t)cap, sizeof(int32_t));
    de[k] = calloc((size_t)cap, sizeof(int32_t));
  }
  for (int t = 0; t < ticks; t++) {
    int na = yp_c_sense(&wc, so[0]), nb_ = yp_c_sense(&wa, so[1]), nr = yp_rust_sense(&wr, so[2]);
    CHECK(na == nb_ && na == nr);
    CHECK(memcmp(so[0], so[1], (size_t)cap * SENSORS * 4) == 0 && memcmp(so[0], so[2], (size_t)cap * SENSORS * 4) == 0);
    for (int i = 0; i < wc.used; i++)
      for (int k = 0; k < SENSORS; k++) { int v = so[0][i * SENSORS + k]; CHECK(v >= 0 && v <= (k == 4 ? 15 : 255)); }
    int64_t alen = (int64_t)(rd8(&r) % (unsigned)(cap + 1));
    for (int i = 0; i < cap; i++) act[i] = (int32_t)rd32(&r);
    int32_t nb[3], nd[3];
    yp_c_act(&wc, act, alen, thresh, bi[0], &nb[0], de[0], &nd[0]);
    yp_c_act(&wa, act, alen, thresh, bi[1], &nb[1], de[1], &nd[1]);
    yp_rust_act(&wr, act, alen, thresh, bi[2], &nb[2], de[2], &nd[2]);
    for (int k = 1; k < 3; k++) {
      CHECK(nb[k] == nb[0] && nd[k] == nd[0]);
      CHECK(memcmp(bi[k], bi[0], (size_t)nb[0] * 4) == 0 && memcmp(de[k], de[0], (size_t)nd[0] * 4) == 0);
    }
    CHECK(weq(&wc, &wa) && weq(&wc, &wr));
    for (int i = 0; i < wc.used; i++) {
      CHECK(wc.x[i] >= 0 && wc.x[i] < wc.w && wc.y[i] >= 0 && wc.y[i] < wc.h);
      CHECK(wc.heading[i] >= 0 && wc.heading[i] < NDIR);
    }
  }
  for (int k = 0; k < 3; k++) { free(so[k]); free(bi[k]); free(de[k]); }
  free(act); wfree(&base); wfree(&wc); wfree(&wa); wfree(&wr);
  return 0;
}
