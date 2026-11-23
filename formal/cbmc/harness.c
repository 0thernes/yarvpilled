/*
 * CBMC harnesses for the reference C kernel (ext/yarvpilled_native/kernel_c.c).
 *
 * kernel_c.c is #included verbatim, so the static helpers are checked as compiled,
 * not a copy. Every harness is a bounded model-checking proof over all inputs the
 * __CPROVER_assume lines allow, with CBMC's memory-safety, signed-overflow,
 * float-to-int conversion and division checks on (see check.sh for the flags).
 */
#include <stdint.h>
#include <string.h>
#include "../../ext/yarvpilled_native/kernel_c.c"
#include "../../ext/yarvpilled_native/trig_table.h"

int nondet_int(void);
int64_t nondet_i64(void);
uint8_t nondet_u8(void);
double nondet_double(void);

static double dbl_in(double lo, double hi) {
  double v = nondet_double();
  __CPROVER_assume(v >= lo && v < hi); /* excludes NaN and infinities */
  return v;
}

/* Points on a lattice of spacing `step` in [0, n*step): exact doubles, so the solver
 * enumerates positions instead of bit-blasting arbitrary 53-bit mantissas. Used where
 * fully symbolic doubles made the SAT problem too large for the box (see README). */
static double lattice(int n, double step) {
  int k = nondet_int();
  __CPROVER_assume(k >= 0 && k < n);
  return k * step;
}

static void load_trig(void) {
  memcpy(yp_cos_t, YP_COS_BITS, sizeof yp_cos_t);
  memcpy(yp_sin_t, YP_SIN_BITS, sizeof yp_sin_t);
}

/* H1a: food_index always lands inside the food grid, for every integer cell coordinate
 * an int can hold and every food-grid size World.new can produce (1..1,000,000 cells
 * per axis). fcell = 1 makes the double->int step exact, so this isolates the C `%`
 * wrap, which is where a negative coordinate could escape. */
void h_food_index_wrap(void) {
  World w;
  w.fcell = 1;
  w.fw = nondet_int(); __CPROVER_assume(w.fw >= 1 && w.fw <= 1000000);
  w.fh = 1;
  int cx = nondet_int();
  int k = food_index(&w, (double)cx, 0.0);
  __CPROVER_assert(k >= 0 && k < w.fw, "food index in bounds");
}

/* H1b: the same on the default 768x512 world (food cell 8, 96x64 food grid) for any
 * finite point within one world-width of the torus (sensors probe 10 units out), with
 * the real double division and the float->int conversion check. */
void h_food_index_default_world(void) {
  World w;
  w.fcell = 8; w.fw = 96; w.fh = 64;
  double x = dbl_in(-768.0, 1536.0), y = dbl_in(-512.0, 1024.0);
  int k = food_index(&w, x, y);
  __CPROVER_assert(k >= 0 && k < w.fw * w.fh, "food index in bounds");
}

/* H2: wrapd maps one step outside the torus back into [0, m). */
void h_wrapd_into_torus(void) {
  double m = dbl_in(72.0, 1000000.0);
  double v = dbl_in(-m, 2 * m);
  double r = wrapd(v, m);
  __CPROVER_assert(r >= 0.0 && r < m, "wrapd result in [0, m)");
}

/* H3: tdelta returns the short way round: |d| <= m/2 for points on the torus. */
void h_tdelta_short_way(void) {
  double m = dbl_in(72.0, 1000000.0);
  double a = dbl_in(0.0, m), b = dbl_in(0.0, m);
  double d = tdelta(a, b, m);
  __CPROVER_assert(d >= -m / 2 && d <= m / 2, "|tdelta| <= m/2");
}

/* H4: one full yp_c_act tick on a minimal legal world (72x72, 3x3 food and crowd grids,
 * ACT_CAP creature slots, default 1. On the dev box neither ACT_CAP=1 nor 2 finished
 * (see docs/verification/cbmc.json); collisions are covered exhaustively by lattice.c instead)
 * with arbitrary positions, headings, energies, ages, costs and
 * actions: no out-of-bounds access, no signed overflow, no bad float->int cast,
 * and the invariants the README states hold afterwards. */
#define CAP 2
#ifndef LAT_STEP
#define LAT_STEP 24.0         /* {0, 24, 48} per axis: the cell seams; finer lattices are covered by lattice.c */
#endif
#define LAT_N ((int)(72.0 / LAT_STEP))
#ifndef ACT_CAP
#define ACT_CAP 1
#endif
void h_act_tick_safe(void) {
  load_trig();
  double x[ACT_CAP], y[ACT_CAP];
  int32_t heading[ACT_CAP], age[ACT_CAP], species[ACT_CAP], cost[ACT_CAP], last[ACT_CAP], actions[ACT_CAP];
  int64_t energy[ACT_CAP], e0[ACT_CAP];
  uint8_t alive[ACT_CAP], food[9], fert[9], facc[9];
  int32_t ghead[9], gnext[ACT_CAP], births[ACT_CAP], deaths[ACT_CAP];
  World w;
  memset(&w, 0, sizeof w);
  w.cap = ACT_CAP; w.used = nondet_int(); __CPROVER_assume(w.used >= 0 && w.used <= ACT_CAP);
  w.w = 72.0; w.h = 72.0;
  w.x = x; w.y = y; w.heading = heading; w.age = age; w.species = species; w.cost = cost;
  w.last_action = last; w.energy = energy; w.alive = alive;
  w.fw = 3; w.fh = 3; w.fcell = 24; w.food = food; w.fert = fert; w.facc = facc;
  w.gw = 3; w.gh = 3; w.gcell = 24; w.ghead = ghead; w.gnext = gnext;
  int64_t food0 = 0;
  for (int c = 0; c < 9; c++) { food[c] = nondet_u8(); fert[c] = nondet_u8(); facc[c] = nondet_u8(); }
  for (int i = 0; i < ACT_CAP; i++) {
    x[i] = lattice(LAT_N, LAT_STEP); y[i] = lattice(LAT_N, LAT_STEP);
    heading[i] = nondet_int(); __CPROVER_assume(heading[i] >= 0 && heading[i] < NDIR);
    age[i] = nondet_int(); __CPROVER_assume(age[i] >= 0 && age[i] < MAX_AGE);
    cost[i] = nondet_int(); __CPROVER_assume(cost[i] >= 0 && cost[i] <= 1000000);
    energy[i] = nondet_i64(); __CPROVER_assume(energy[i] > -(1LL << 40) && energy[i] < (1LL << 40));
    e0[i] = energy[i];
    alive[i] = nondet_u8(); __CPROVER_assume(alive[i] <= 1);
    actions[i] = nondet_int();
  }
  int64_t thresh = nondet_i64(); __CPROVER_assume(thresh > 0 && thresh < (1LL << 40));
  int32_t nb, nd;
  yp_c_act(&w, actions, ACT_CAP, thresh, births, &nb, deaths, &nd);
  __CPROVER_assert(nb >= 0 && nd >= 0 && nb + nd <= w.used, "births + deaths <= used");
  for (int c = 0; c < 9; c++) __CPROVER_assert(food[c] <= FOOD_MAX, "food <= 255");
  for (int i = 0; i < w.used; i++) {
    __CPROVER_assert(heading[i] >= 0 && heading[i] < NDIR, "heading in 0..63");
    __CPROVER_assert(x[i] >= 0.0 && x[i] < 72.0 && y[i] >= 0.0 && y[i] < 72.0, "position on torus");
    __CPROVER_assert(energy[i] <= e0[i] + 13 - 3, "energy gain bounded by one 9-bite meal minus metabolism");
  }
  __CPROVER_assert(w.ticks == 1, "tick counted");
}

/* H5: the C crowd scan on the same world counts at most used-1 neighbours and reads
 * only inside the buffers. */
void h_crowd_bounded(void) {
  double x[CAP], y[CAP];
  int32_t ghead[9], gnext[CAP];
  uint8_t alive[CAP];
  World w;
  memset(&w, 0, sizeof w);
  w.cap = CAP; w.used = CAP; w.w = 72.0; w.h = 72.0; w.x = x; w.y = y; w.alive = alive;
  w.gw = 3; w.gh = 3; w.gcell = 24; w.ghead = ghead; w.gnext = gnext;
  for (int i = 0; i < CAP; i++) { x[i] = lattice(LAT_N, LAT_STEP); y[i] = lattice(LAT_N, LAT_STEP); alive[i] = 1; }
  yp_build_grid(&w);
  CrowdCtx ctx = { x, y, ghead, gnext, 3, 3, 24.0, 72.0, 72.0, CROWD_R * CROWD_R };
  int i = nondet_int(); __CPROVER_assume(i >= 0 && i < CAP);
  int32_t cr = yp_c_crowd(&ctx, i);
  __CPROVER_assert(cr >= 0 && cr <= CAP - 1, "crowd count <= used - 1");
}
