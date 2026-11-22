/*
 * kernel_c.c -- reference C world-loop kernel (no Ruby API in here).
 * lib/yarvpilled/world_ruby.rb is a line-for-line Ruby port; the Rust and
 * asm backends must stay bit-identical to this file.
 */
#include <math.h>
#include "world.h"

double yp_cos_t[NDIR], yp_sin_t[NDIR];

static inline int food_index(World *w, double x, double y) {
  int cx = (int)(x / w->fcell), cy = (int)(y / w->fcell);
  cx %= w->fw; if (cx < 0) cx += w->fw;
  cy %= w->fh; if (cy < 0) cy += w->fh;
  return cy * w->fw + cx;
}

static inline double wrapd(double v, double m) {
  if (v < 0) v += m;
  if (v >= m) v -= m;
  return v;
}

static inline double tdelta(double a, double b, double m) {
  double d = b - a;
  if (d > m / 2) d -= m;
  if (d < -m / 2) d += m;
  return d;
}

void yp_build_grid(World *w) {
  int n = w->gw * w->gh;
  for (int i = 0; i < n; i++) w->ghead[i] = -1;
  for (int i = 0; i < w->used; i++) {
    if (!w->alive[i]) continue;
    int gx = (int)(w->x[i] / w->gcell) % w->gw, gy = (int)(w->y[i] / w->gcell) % w->gh;
    int c = gy * w->gw + gx;
    w->gnext[i] = w->ghead[c];
    w->ghead[c] = i;
  }
}

/* Crowd sensing: neighbours within CROWD_R in the 3x3 grid neighbourhood.
 * This is the hottest kernel; crowd_x86_64.S is the hand-written asm twin. */
int32_t yp_c_crowd(const CrowdCtx *c, int32_t i) {
  double px = c->x[i], py = c->y[i];
  int gx = (int)(px / c->gcell), gy = (int)(py / c->gcell);
  int cr = 0;
  for (int oy = -1; oy <= 1; oy++) for (int ox = -1; ox <= 1; ox++) {
    int cx = (gx + ox + c->gw) % c->gw, cy = (gy + oy + c->gh) % c->gh;
    for (int j = c->ghead[cy * c->gw + cx]; j >= 0; j = c->gnext[j]) {
      if (j == i) continue;
      double dx = tdelta(px, c->x[j], c->w), dy = tdelta(py, c->y[j], c->h);
      if (dx * dx + dy * dy < c->r2) cr++;
    }
  }
  return cr;
}

static int32_t sense_with(World *w, int32_t *out, int32_t (*crowd)(const CrowdCtx *, int32_t)) {
  yp_build_grid(w);
  CrowdCtx ctx = { w->x, w->y, w->ghead, w->gnext, w->gw, w->gh, (double)w->gcell, w->w, w->h, CROWD_R * CROWD_R };
  int alive = 0;
  for (int i = 0; i < w->used; i++) {
    int32_t *o = out + (long)i * SENSORS;
    if (!w->alive[i]) { for (int k = 0; k < SENSORS; k++) o[k] = 0; continue; }
    alive++;
    int h = w->heading[i];
    int hl = (h - 6) & (NDIR - 1), hr = (h + 6) & (NDIR - 1);
    double px = w->x[i], py = w->y[i];
    o[0] = w->food[food_index(w, px + yp_cos_t[h] * 10.0, py + yp_sin_t[h] * 10.0)];
    o[1] = w->food[food_index(w, px + yp_cos_t[hl] * 10.0, py + yp_sin_t[hl] * 10.0)];
    o[2] = w->food[food_index(w, px + yp_cos_t[hr] * 10.0, py + yp_sin_t[hr] * 10.0)];
    int64_t en = w->energy[i] / 4; if (en > 255) en = 255; if (en < 0) en = 0;
    o[3] = (int32_t)en;
    int cr = crowd(&ctx, i);
    o[4] = cr > 15 ? 15 : cr;
    int ag = w->age[i] / 8; o[5] = ag > 255 ? 255 : ag;
  }
  return alive;
}

#ifdef YP_NO_ASM
int32_t yp_asm_crowd(const CrowdCtx *c, int32_t i) { return yp_c_crowd(c, i); }
#endif

int32_t yp_c_sense(World *w, int32_t *out) {
  return sense_with(w, out, w->backend == BACKEND_ASM ? yp_asm_crowd : yp_c_crowd);
}

void yp_c_act(World *w, const int32_t *actions, int64_t alen, int64_t thresh,
              int32_t *births, int32_t *nb, int32_t *deaths, int32_t *nd) {
  int nf = w->fw * w->fh;
  *nb = *nd = 0;
  for (int c = 0; c < nf; c++) {
    int acc = w->facc[c] + w->fert[c];
    int f = w->food[c] + (acc >> 8);
    w->facc[c] = (uint8_t)(acc & 255);
    w->food[c] = (uint8_t)(f > FOOD_MAX ? FOOD_MAX : f);
  }
  for (int i = 0; i < w->used; i++) {
    if (!w->alive[i]) continue;
    int a = i < alen ? (actions[i] & 3) : 0;
    w->last_action[i] = a;
    double speed;
    switch (a) {
      case 0: speed = 0.35; break;
      case 1: w->heading[i] = (w->heading[i] - 3) & (NDIR - 1); speed = 1.0; break;
      case 2: w->heading[i] = (w->heading[i] + 3) & (NDIR - 1); speed = 1.0; break;
      default: speed = 2.4; break;
    }
    int h = w->heading[i];
    w->x[i] = wrapd(w->x[i] + yp_cos_t[h] * speed, w->w);
    w->y[i] = wrapd(w->y[i] + yp_sin_t[h] * speed, w->h);
    int fc = food_index(w, w->x[i], w->y[i]);
    int bite = a == 0 ? 9 : 4;
    int take = w->food[fc] < bite ? w->food[fc] : bite;
    w->food[fc] -= take;
    w->eaten_total += take;
    w->energy[i] += take + take / 2;
    w->energy[i] -= 3 + w->cost[i] + (a == 3 ? 3 : 0);
    w->age[i]++;
  }
  yp_build_grid(w);
  for (int i = 0; i < w->used; i++) {
    if (!w->alive[i]) continue;
    int gx = (int)(w->x[i] / w->gcell), gy = (int)(w->y[i] / w->gcell);
    for (int oy = -1; oy <= 1; oy++) for (int ox = -1; ox <= 1; ox++) {
      int cx = (gx + ox + w->gw) % w->gw, cy = (gy + oy + w->gh) % w->gh;
      for (int j = w->ghead[cy * w->gw + cx]; j >= 0; j = w->gnext[j]) {
        if (j <= i) continue;
        double dx = tdelta(w->x[i], w->x[j], w->w), dy = tdelta(w->y[i], w->y[j], w->h);
        double d2 = dx * dx + dy * dy;
        if (d2 >= (2 * RADIUS) * (2 * RADIUS) || d2 == 0.0) continue;
        double d = sqrt(d2), push = (2 * RADIUS - d) * 0.5 / d;
        w->x[i] = wrapd(w->x[i] - dx * push, w->w); w->y[i] = wrapd(w->y[i] - dy * push, w->h);
        w->x[j] = wrapd(w->x[j] + dx * push, w->w); w->y[j] = wrapd(w->y[j] + dy * push, w->h);
      }
    }
  }
  for (int i = 0; i < w->used; i++) {
    if (!w->alive[i]) continue;
    if (w->energy[i] <= 0 || w->age[i] >= MAX_AGE) {
      w->alive[i] = 0;
      int fc = food_index(w, w->x[i], w->y[i]);
      int f = w->food[fc] + 40;
      w->food[fc] = (uint8_t)(f > FOOD_MAX ? FOOD_MAX : f);
      w->deaths_total++;
      deaths[(*nd)++] = i;
    } else if (w->energy[i] >= thresh) {
      births[(*nb)++] = i;
    }
  }
  w->ticks++;
}
