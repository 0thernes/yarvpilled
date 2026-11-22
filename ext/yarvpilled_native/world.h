/*
 * world.h -- shared World layout for the three world-loop kernels:
 *   kernel_c.c         plain C (the reference)
 *   crowd_x86_64.S     hand-written x86-64 asm for the crowd-sensing scan,
 *                      used by the "asm" backend (rest of the loop is C)
 *   ../yarvpilled_rust Rust staticlib (#[repr(C)] mirror of this struct)
 * All kernels operate on plain buffers; the Ruby glue in world.c is shared,
 * so every backend pays exactly the same Ruby<->native conversion cost.
 */
#ifndef YARVPILLED_WORLD_H
#define YARVPILLED_WORLD_H
#include <stdint.h>

#define NDIR 64
#define SENSORS 6
#define RADIUS 4.0
#define CROWD_R 20.0
#define MAX_AGE 900
#define FOOD_MAX 255

enum { BACKEND_C = 0, BACKEND_RUST = 1, BACKEND_ASM = 2 };

/* Field order/types are mirrored in ext/yarvpilled_rust/src/lib.rs. Do not reorder. */
typedef struct World {
  int32_t cap, used;
  double w, h;
  double *x, *y;
  int32_t *heading, *age, *species, *cost, *last_action;
  int64_t *energy;
  uint8_t *alive;
  int32_t fw, fh, fcell;
  uint8_t *food, *fert, *facc;
  int32_t gw, gh, gcell;
  int32_t *ghead, *gnext;
  int64_t eaten_total, ticks, deaths_total;
  int32_t backend;
  int32_t *sbuf, *abuf, *bbuf, *dbuf; /* scratch: sensors, actions, births, deaths */
} World;

/* Context handed to the asm crowd kernel (offsets are hard-coded in the .S). */
typedef struct CrowdCtx {
  const double *x;      /*  0 */
  const double *y;      /*  8 */
  const int32_t *ghead; /* 16 */
  const int32_t *gnext; /* 24 */
  int32_t gw, gh;       /* 32, 36 */
  double gcell;         /* 40 */
  double w, h;          /* 48, 56 */
  double r2;            /* 64 */
} CrowdCtx;

extern double yp_cos_t[NDIR], yp_sin_t[NDIR];

int32_t yp_c_sense(World *w, int32_t *out);
void yp_c_act(World *w, const int32_t *actions, int64_t alen, int64_t thresh,
              int32_t *births, int32_t *nb, int32_t *deaths, int32_t *nd);
int32_t yp_c_crowd(const CrowdCtx *c, int32_t i);
int32_t yp_asm_crowd(const CrowdCtx *c, int32_t i);
void yp_build_grid(World *w);

#ifdef YP_HAVE_RUST
int32_t yp_rust_sense(World *w, int32_t *out);
void yp_rust_act(World *w, const int32_t *actions, int64_t alen, int64_t thresh,
                 int32_t *births, int32_t *nb, int32_t *deaths, int32_t *nd);
#endif
#endif
