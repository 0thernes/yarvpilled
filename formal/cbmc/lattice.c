/*
 * Exhaustive lattice check: the complement to h_crowd_bounded / h_act_tick_safe.
 *
 * CBMC proves the tick over a coarse position lattice (fully symbolic doubles do not
 * fit in the box's memory). This program enumerates a finer one completely: two
 * creatures on a 72x72 world (the smallest legal one, 3x3 crowd grid), every position on
 * a 3-unit lattice (24^4 = 331,776 placements, crossing both 24-unit cell seams and the
 * torus edge) x all 16 action pairs, with headings/energies/costs/food drawn from a fixed
 * xorshift seed. Built with ASan + UBSan (+ float-cast-overflow), so any out-of-bounds
 * access, signed overflow or bad float->int cast aborts. For every case it checks the
 * same post-conditions as the CBMC harness, that the asm crowd scan equals the C one,
 * and (when the Rust kernel is linked) that the Rust tick is bit-identical to C.
 *
 *   formal/cbmc/lattice.sh            (builds and runs it, ~1-2 min)
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "world.h"
#include "trig_table.h"

#define CAP 2
#define STEP 3.0
#define N 24

typedef struct {
  double x[CAP], y[CAP];
  int32_t heading[CAP], age[CAP], species[CAP], cost[CAP], last[CAP];
  int64_t energy[CAP];
  uint8_t alive[CAP], food[9], fert[9], facc[9];
  int32_t ghead[9], gnext[CAP];
  World w;
} Box;

static uint64_t rs = 0x9E3779B97F4A7C15ULL;
static uint64_t rnd(void) { rs ^= rs << 13; rs ^= rs >> 7; rs ^= rs << 17; return rs; }

static void wire(Box *b) {
  World *w = &b->w;
  w->x = b->x; w->y = b->y; w->heading = b->heading; w->age = b->age; w->species = b->species;
  w->cost = b->cost; w->last_action = b->last; w->energy = b->energy; w->alive = b->alive;
  w->food = b->food; w->fert = b->fert; w->facc = b->facc; w->ghead = b->ghead; w->gnext = b->gnext;
}

static long fails = 0;
#define CHECK(c, msg) do { if (!(c)) { if (fails++ < 20) fprintf(stderr, "FAIL %s (case %ld)\n", msg, cases); } } while (0)

int main(void) {
  memcpy(yp_cos_t, YP_COS_BITS, sizeof yp_cos_t);
  memcpy(yp_sin_t, YP_SIN_BITS, sizeof yp_sin_t);
  long cases = 0, crowd_cmp = 0, rust_cmp = 0;
  for (int ax = 0; ax < N; ax++) for (int ay = 0; ay < N; ay++)
  for (int bx = 0; bx < N; bx++) for (int by = 0; by < N; by++)
  for (int acts = 0; acts < 16; acts++) {
    Box b; memset(&b, 0, sizeof b);
    World *w = &b.w;
    w->cap = CAP; w->used = CAP; w->w = 72.0; w->h = 72.0;
    w->fw = 3; w->fh = 3; w->fcell = 24; w->gw = 3; w->gh = 3; w->gcell = 24;
    wire(&b);
    b.x[0] = ax * STEP; b.y[0] = ay * STEP; b.x[1] = bx * STEP; b.y[1] = by * STEP;
    for (int i = 0; i < CAP; i++) {
      b.heading[i] = (int32_t)(rnd() & 63);
      b.age[i] = (int32_t)(rnd() % MAX_AGE);
      b.cost[i] = (int32_t)(rnd() % 64);
      b.energy[i] = (int64_t)(rnd() % 4000) - 100;
      b.alive[i] = 1;
    }
    for (int c = 0; c < 9; c++) { b.food[c] = (uint8_t)rnd(); b.fert[c] = (uint8_t)rnd(); b.facc[c] = (uint8_t)rnd(); }
    int32_t actions[CAP] = { acts & 3, acts >> 2 };
    int64_t e0[CAP] = { b.energy[0], b.energy[1] };

    /* crowd: asm vs C on the pre-tick positions */
    yp_build_grid(w);
    CrowdCtx ctx = { b.x, b.y, b.ghead, b.gnext, 3, 3, 24.0, 72.0, 72.0, CROWD_R * CROWD_R };
    for (int i = 0; i < CAP; i++) {
      int32_t c1 = yp_c_crowd(&ctx, i), c2 = yp_asm_crowd(&ctx, i);
      CHECK(c1 == c2, "asm crowd == C crowd");
      CHECK(c1 >= 0 && c1 <= CAP - 1, "crowd <= used-1");
      crowd_cmp++;
    }

    Box r = b; wire(&r);
    int32_t births[CAP], deaths[CAP], nb, nd;
    yp_c_act(w, actions, CAP, 3000, births, &nb, deaths, &nd);
    CHECK(nb >= 0 && nd >= 0 && nb + nd <= CAP, "births + deaths <= used");
    for (int c = 0; c < 9; c++) CHECK(b.food[c] <= FOOD_MAX, "food <= 255");
    for (int i = 0; i < CAP; i++) {
      CHECK(b.heading[i] >= 0 && b.heading[i] < NDIR, "heading in 0..63");
      CHECK(b.x[i] >= 0.0 && b.x[i] < 72.0 && b.y[i] >= 0.0 && b.y[i] < 72.0, "position on torus");
      CHECK(b.energy[i] <= e0[i] + 10, "energy gain bounded");
    }
#ifdef YP_HAVE_RUST
    int32_t rb[CAP], rd[CAP], rnb, rnd_;
    r.w.backend = BACKEND_RUST;
    yp_rust_act(&r.w, actions, CAP, 3000, rb, &rnb, rd, &rnd_);
    CHECK(rnb == nb && rnd_ == nd, "rust births/deaths == C");
    CHECK(memcmp(r.x, b.x, sizeof b.x) == 0 && memcmp(r.y, b.y, sizeof b.y) == 0, "rust positions bit-identical");
    CHECK(memcmp(r.energy, b.energy, sizeof b.energy) == 0 && memcmp(r.food, b.food, 9) == 0 &&
          memcmp(r.facc, b.facc, 9) == 0 && memcmp(r.alive, b.alive, CAP) == 0 &&
          memcmp(r.heading, b.heading, sizeof b.heading) == 0, "rust state bit-identical");
    rust_cmp++;
#endif
    cases++;
  }
  printf("{\"tool\": \"formal/cbmc/lattice.sh\", \"cases\": %ld, \"crowd_asm_vs_c\": %ld, \"rust_vs_c_ticks\": %ld, \"failures\": %ld, \"passed\": %s}\n",
         cases, crowd_cmp, rust_cmp, fails, fails ? "false" : "true");
  return fails ? 1 : 0;
}
