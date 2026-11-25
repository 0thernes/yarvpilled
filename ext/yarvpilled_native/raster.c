/*
 * raster.c -- tiny software rasterizer on RGB24 Ruby Strings (ruby.h only).
 * Every pixel in the demo video is drawn by these routines (or by the
 * pure-Ruby fallback in lib/yarvpilled/raster_ruby.rb when the extension
 * is not compiled).
 */
#include <ruby.h>
#include <math.h>
#include <string.h>
#include <limits.h>

typedef struct { unsigned char *p; int w, h; } Buf;

static Buf get_buf(VALUE str, VALUE vw, VALUE vh) {
  Buf b;
  StringValue(str);
  rb_str_modify(str);
  b.w = NUM2INT(vw); b.h = NUM2INT(vh);
  /* sizes are checked in 64-bit (long is 32 bits on Windows); bad sizes raise instead of overrunning */
  if (b.w <= 0 || b.h <= 0 || RSTRING_LEN(str) < (long long)b.w * b.h * 3) rb_raise(rb_eArgError, "buffer too small");
  b.p = (unsigned char *)RSTRING_PTR(str);
  return b;
}

static inline void blend(Buf *b, int x, int y, int r, int g, int bl, int a) {
  if (x < 0 || y < 0 || x >= b->w || y >= b->h || a <= 0) return;
  if (a > 255) a = 255;
  unsigned char *q = b->p + ((long)y * b->w + x) * 3;
  q[0] = (unsigned char)(q[0] + ((r - q[0]) * a) / 255);
  q[1] = (unsigned char)(q[1] + ((g - q[1]) * a) / 255);
  q[2] = (unsigned char)(q[2] + ((bl - q[2]) * a) / 255);
}

static inline void add(Buf *b, int x, int y, int r, int g, int bl, int a) {
  if (x < 0 || y < 0 || x >= b->w || y >= b->h || a <= 0) return;
  unsigned char *q = b->p + ((long)y * b->w + x) * 3;
  int v;
  v = q[0] + r * a / 255; q[0] = (unsigned char)(v > 255 ? 255 : v);
  v = q[1] + g * a / 255; q[1] = (unsigned char)(v > 255 ? 255 : v);
  v = q[2] + bl * a / 255; q[2] = (unsigned char)(v > 255 ? 255 : v);
}

#define BUF_ARGS VALUE str, VALUE vw, VALUE vh
#define RGBA VALUE vr, VALUE vg, VALUE vb, VALUE va
#define C_RGBA int r = NUM2INT(vr), g = NUM2INT(vg), bl = NUM2INT(vb), a = NUM2INT(va)

static VALUE r_fill(VALUE m, BUF_ARGS, VALUE vr, VALUE vg, VALUE vb) {
  Buf b = get_buf(str, vw, vh);
  unsigned char c[3] = { (unsigned char)NUM2INT(vr), (unsigned char)NUM2INT(vg), (unsigned char)NUM2INT(vb) };
  long n = (long)b.w * b.h;
  for (long i = 0; i < n; i++) memcpy(b.p + i * 3, c, 3);
  return str;
}

static VALUE r_rect(VALUE m, BUF_ARGS, VALUE vx, VALUE vy, VALUE vrw, VALUE vrh, RGBA) {
  Buf b = get_buf(str, vw, vh); C_RGBA;
  int x0 = NUM2INT(vx), y0 = NUM2INT(vy), rw = NUM2INT(vrw), rh = NUM2INT(vrh);
  for (int y = y0; y < y0 + rh; y++) for (int x = x0; x < x0 + rw; x++) blend(&b, x, y, r, g, bl, a);
  return str;
}

/* additive radial glow, quadratic falloff */
static VALUE r_glow(VALUE m, BUF_ARGS, VALUE vcx, VALUE vcy, VALUE vrad, RGBA) {
  Buf b = get_buf(str, vw, vh); C_RGBA;
  double cx = NUM2DBL(vcx), cy = NUM2DBL(vcy), rad = NUM2DBL(vrad);
  if (rad <= 0) return str;
  for (int y = (int)(cy - rad); y <= (int)(cy + rad); y++)
    for (int x = (int)(cx - rad); x <= (int)(cx + rad); x++) {
      double dx = x + 0.5 - cx, dy = y + 0.5 - cy, d = sqrt(dx * dx + dy * dy) / rad;
      if (d >= 1.0) continue;
      double f = (1.0 - d) * (1.0 - d);
      add(&b, x, y, r, g, bl, (int)(a * f));
    }
  return str;
}

/* anti-aliased filled disc (alpha blend) */
static VALUE r_disc(VALUE m, BUF_ARGS, VALUE vcx, VALUE vcy, VALUE vrad, RGBA) {
  Buf b = get_buf(str, vw, vh); C_RGBA;
  double cx = NUM2DBL(vcx), cy = NUM2DBL(vcy), rad = NUM2DBL(vrad);
  for (int y = (int)(cy - rad - 1); y <= (int)(cy + rad + 1); y++)
    for (int x = (int)(cx - rad - 1); x <= (int)(cx + rad + 1); x++) {
      double dx = x + 0.5 - cx, dy = y + 0.5 - cy, d = sqrt(dx * dx + dy * dy);
      double cov = rad + 0.5 - d;
      if (cov <= 0) continue;
      if (cov > 1) cov = 1;
      blend(&b, x, y, r, g, bl, (int)(a * cov));
    }
  return str;
}

/* ring outline */
static VALUE r_ring(VALUE m, BUF_ARGS, VALUE vcx, VALUE vcy, VALUE vrad, VALUE vth, RGBA) {
  Buf b = get_buf(str, vw, vh); C_RGBA;
  double cx = NUM2DBL(vcx), cy = NUM2DBL(vcy), rad = NUM2DBL(vrad), th = NUM2DBL(vth);
  for (int y = (int)(cy - rad - th - 1); y <= (int)(cy + rad + th + 1); y++)
    for (int x = (int)(cx - rad - th - 1); x <= (int)(cx + rad + th + 1); x++) {
      double dx = x + 0.5 - cx, dy = y + 0.5 - cy, d = fabs(sqrt(dx * dx + dy * dy) - rad);
      double cov = th / 2 + 0.5 - d;
      if (cov <= 0) continue;
      if (cov > 1) cov = 1;
      blend(&b, x, y, r, g, bl, (int)(a * cov));
    }
  return str;
}

/* arc of a ring from angle a0 to a1 (radians), for gauges */
static VALUE r_arc(VALUE m, BUF_ARGS, VALUE vcx, VALUE vcy, VALUE vrad, VALUE vth, VALUE va0, VALUE va1, RGBA) {
  Buf b = get_buf(str, vw, vh); C_RGBA;
  double cx = NUM2DBL(vcx), cy = NUM2DBL(vcy), rad = NUM2DBL(vrad), th = NUM2DBL(vth);
  double a0 = NUM2DBL(va0), a1 = NUM2DBL(va1);
  for (int y = (int)(cy - rad - th - 1); y <= (int)(cy + rad + th + 1); y++)
    for (int x = (int)(cx - rad - th - 1); x <= (int)(cx + rad + th + 1); x++) {
      double dx = x + 0.5 - cx, dy = y + 0.5 - cy, d = fabs(sqrt(dx * dx + dy * dy) - rad);
      double cov = th / 2 + 0.5 - d;
      if (cov <= 0) continue;
      double ang = atan2(dy, dx); if (ang < a0) ang += 2 * M_PI;
      if (ang < a0 || ang > a1) continue;
      if (cov > 1) cov = 1;
      blend(&b, x, y, r, g, bl, (int)(a * cov));
    }
  return str;
}

/* filled regular polygon with 4x vertical supersampling on edges */
static VALUE r_ngon(VALUE m, BUF_ARGS, VALUE vcx, VALUE vcy, VALUE vrad, VALUE vsides, VALUE vrot, RGBA) {
  Buf b = get_buf(str, vw, vh); C_RGBA;
  double cx = NUM2DBL(vcx), cy = NUM2DBL(vcy), rad = NUM2DBL(vrad), rot = NUM2DBL(vrot);
  int n = NUM2INT(vsides); if (n < 3) n = 3; if (n > 12) n = 12;
  double px[12], py[12];
  for (int k = 0; k < n; k++) { px[k] = cx + cos(rot + 2 * M_PI * k / n) * rad; py[k] = cy + sin(rot + 2 * M_PI * k / n) * rad; }
  for (int y = (int)(cy - rad - 1); y <= (int)(cy + rad + 1); y++)
    for (int x = (int)(cx - rad - 1); x <= (int)(cx + rad + 1); x++) {
      int hits = 0;
      for (int s = 0; s < 4; s++) {
        double sx = x + 0.25 + 0.5 * (s & 1), sy = y + 0.25 + 0.5 * (s >> 1);
        int inside = 1;
        for (int k = 0; k < n; k++) {
          int k2 = (k + 1) % n;
          double cr = (px[k2] - px[k]) * (sy - py[k]) - (py[k2] - py[k]) * (sx - px[k]);
          if (cr < 0) { inside = 0; break; }
        }
        hits += inside;
      }
      if (hits) blend(&b, x, y, r, g, bl, a * hits / 4);
    }
  return str;
}

/* Wu-style anti-aliased line; additive when vadd is truthy */
static VALUE r_line(VALUE m, BUF_ARGS, VALUE vx0, VALUE vy0, VALUE vx1, VALUE vy1, RGBA, VALUE vadd) {
  Buf b = get_buf(str, vw, vh); C_RGBA;
  double x0 = NUM2DBL(vx0), y0 = NUM2DBL(vy0), x1 = NUM2DBL(vx1), y1 = NUM2DBL(vy1);
  int additive = RTEST(vadd);
  double dx = x1 - x0, dy = y1 - y0;
  int steep = fabs(dy) > fabs(dx);
  double len = steep ? fabs(dy) : fabs(dx);
  int steps = (int)ceil(len); if (steps < 1) steps = 1;
  for (int s = 0; s <= steps; s++) {
    double t = (double)s / steps, x = x0 + dx * t, y = y0 + dy * t;
    if (steep) {
      int xi = (int)floor(x); double f = x - xi;
      if (additive) { add(&b, xi, (int)y, r, g, bl, (int)(a * (1 - f))); add(&b, xi + 1, (int)y, r, g, bl, (int)(a * f)); }
      else { blend(&b, xi, (int)y, r, g, bl, (int)(a * (1 - f))); blend(&b, xi + 1, (int)y, r, g, bl, (int)(a * f)); }
    } else {
      int yi = (int)floor(y); double f = y - yi;
      if (additive) { add(&b, (int)x, yi, r, g, bl, (int)(a * (1 - f))); add(&b, (int)x, yi + 1, r, g, bl, (int)(a * f)); }
      else { blend(&b, (int)x, yi, r, g, bl, (int)(a * (1 - f))); blend(&b, (int)x, yi + 1, r, g, bl, (int)(a * f)); }
    }
  }
  return str;
}

/* multiply a region by num/256 (trail fade) */
static VALUE r_scale(VALUE m, BUF_ARGS, VALUE vx, VALUE vy, VALUE vrw, VALUE vrh, VALUE vnum) {
  Buf b = get_buf(str, vw, vh);
  int x0 = NUM2INT(vx), y0 = NUM2INT(vy), rw = NUM2INT(vrw), rh = NUM2INT(vrh), num = NUM2INT(vnum);
  for (int y = y0 < 0 ? 0 : y0; y < y0 + rh && y < b.h; y++) {
    unsigned char *q = b.p + ((long)y * b.w + (x0 < 0 ? 0 : x0)) * 3;
    for (int x = x0 < 0 ? 0 : x0; x < x0 + rw && x < b.w; x++, q += 3) {
      q[0] = (unsigned char)(q[0] * num >> 8); q[1] = (unsigned char)(q[1] * num >> 8); q[2] = (unsigned char)(q[2] * num >> 8);
    }
  }
  return str;
}

/* text(buf,w,h, atlas, cw, ch, first, count, string, x, y, r,g,b,a) -> x after */
static VALUE r_text(int argc, VALUE *argv, VALUE m) {
  if (argc != 15) rb_raise(rb_eArgError, "text expects 15 args");
  Buf b = get_buf(argv[0], argv[1], argv[2]);
  VALUE atlas = argv[3]; StringValue(atlas);
  int cw = NUM2INT(argv[4]), ch = NUM2INT(argv[5]), first = NUM2INT(argv[6]), count = NUM2INT(argv[7]);
  VALUE s = argv[8]; StringValue(s);
  int x = NUM2INT(argv[9]), y = NUM2INT(argv[10]);
  int r = NUM2INT(argv[11]), g = NUM2INT(argv[12]), bl = NUM2INT(argv[13]), a = NUM2INT(argv[14]);
  const unsigned char *ap = (const unsigned char *)RSTRING_PTR(atlas);
  if (cw <= 0 || ch <= 0 || count <= 0 || cw > 4096 || ch > 4096 || count > 4096)
    rb_raise(rb_eArgError, "bad glyph size");
  long long stride = (long long)cw * count;
  if (RSTRING_LEN(atlas) < stride * ch) rb_raise(rb_eArgError, "atlas too small");
  const unsigned char *sp = (const unsigned char *)RSTRING_PTR(s);
  long n = RSTRING_LEN(s);
  for (long i = 0; i < n; i++, x += cw) {
    int c = sp[i] - first;
    if (c <= 0 || c >= count) continue; /* space or non-ASCII */
    for (int gy = 0; gy < ch; gy++) for (int gx = 0; gx < cw; gx++) {
      int cov = ap[gy * stride + c * cw + gx];
      if (cov) blend(&b, x + gx, y + gy, r, g, bl, cov * a / 255);
    }
  }
  return INT2FIX(x);
}

/* bilinear heat field: bytes (cols*rows) mapped through palette (768 bytes),
 * drawn additively over region at ox,oy with cell size `cell` */
static VALUE r_heat(int argc, VALUE *argv, VALUE m) {
  if (argc != 10) rb_raise(rb_eArgError, "heat expects 10 args");
  Buf b = get_buf(argv[0], argv[1], argv[2]);
  VALUE field = argv[3]; StringValue(field);
  int cols = NUM2INT(argv[4]), rows = NUM2INT(argv[5]), cell = NUM2INT(argv[6]);
  int ox = NUM2INT(argv[7]), oy = NUM2INT(argv[8]);
  VALUE pal = argv[9]; StringValue(pal);
  if (cols <= 0 || rows <= 0 || cell <= 0 || cell > 4096 || (long long)cols * cell > INT_MAX || (long long)rows * cell > INT_MAX ||
      RSTRING_LEN(field) < (long long)cols * rows || RSTRING_LEN(pal) < 768) rb_raise(rb_eArgError, "bad heat args");
  const unsigned char *f = (const unsigned char *)RSTRING_PTR(field), *p = (const unsigned char *)RSTRING_PTR(pal);
  int W = cols * cell, H = rows * cell;
  for (int y = 0; y < H; y++) {
    double fy = (y + 0.5) / cell - 0.5; int y0 = (int)floor(fy); double ty = fy - y0;
    int ya = (y0 + rows) % rows, yb = (y0 + 1) % rows;
    for (int x = 0; x < W; x++) {
      double fx = (x + 0.5) / cell - 0.5; int x0 = (int)floor(fx); double tx = fx - x0;
      int xa = (x0 + cols) % cols, xb = (x0 + 1) % cols;
      double v = (f[ya * cols + xa] * (1 - tx) + f[ya * cols + xb] * tx) * (1 - ty) +
                 (f[yb * cols + xa] * (1 - tx) + f[yb * cols + xb] * tx) * ty;
      int vi = (int)v; if (vi > 255) vi = 255;
      add(&b, ox + x, oy + y, p[vi * 3], p[vi * 3 + 1], p[vi * 3 + 2], 255);
    }
  }
  return argv[0];
}

/* saturating additive blit of src (sw x sh) onto dst at dx,dy */
static VALUE r_blit_add(VALUE m, VALUE dst, VALUE vdw, VALUE vdh, VALUE src, VALUE vsw, VALUE vsh, VALUE vdx, VALUE vdy) {
  Buf d = get_buf(dst, vdw, vdh);
  StringValue(src);
  int sw = NUM2INT(vsw), sh = NUM2INT(vsh), dx = NUM2INT(vdx), dy = NUM2INT(vdy);
  if (sw < 0 || sh < 0 || RSTRING_LEN(src) < (long long)sw * sh * 3) rb_raise(rb_eArgError, "src too small");
  const unsigned char *s = (const unsigned char *)RSTRING_PTR(src);
  for (int y = 0; y < sh; y++) {
    int ty = y + dy; if (ty < 0 || ty >= d.h) continue;
    for (int x = 0; x < sw; x++) {
      int tx = x + dx; if (tx < 0 || tx >= d.w) continue;
      const unsigned char *ps = s + ((long)y * sw + x) * 3;
      unsigned char *q = d.p + ((long)ty * d.w + tx) * 3;
      for (int k = 0; k < 3; k++) { int v = q[k] + ps[k]; q[k] = (unsigned char)(v > 255 ? 255 : v); }
    }
  }
  return dst;
}

/* CRT scanlines + vignette */
static VALUE r_scanlines(VALUE m, BUF_ARGS, VALUE vstrength) {
  Buf b = get_buf(str, vw, vh);
  int s = NUM2INT(vstrength);
  double cx = b.w / 2.0, cy = b.h / 2.0, maxd = sqrt(cx * cx + cy * cy);
  for (int y = 0; y < b.h; y++) {
    int line = (y & 1) ? 256 - s : 256;
    for (int x = 0; x < b.w; x++) {
      double dx = x - cx, dy = y - cy, d = sqrt(dx * dx + dy * dy) / maxd;
      int vig = (int)(256 - 110 * d * d * d);
      int k = line * vig >> 8;
      unsigned char *q = b.p + ((long)y * b.w + x) * 3;
      q[0] = (unsigned char)(q[0] * k >> 8); q[1] = (unsigned char)(q[1] * k >> 8); q[2] = (unsigned char)(q[2] * k >> 8);
    }
  }
  return str;
}


/* YJIT in 3.4.7 panics (x86_split: opnds.len() <= C_ARG_OPNDS.len()) when it
 * direct-calls fixed-arity cfuncs with more than 5 args, so every
 * many-argument entry point is exposed as variadic (argc, argv) instead. */
static VALUE v_fill(int argc, VALUE *argv, VALUE m) { rb_check_arity(argc, 6, 6); return r_fill(m, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5]); }
static VALUE v_rect(int argc, VALUE *argv, VALUE m) { rb_check_arity(argc, 11, 11); return r_rect(m, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9], argv[10]); }
static VALUE v_glow(int argc, VALUE *argv, VALUE m) { rb_check_arity(argc, 10, 10); return r_glow(m, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9]); }
static VALUE v_disc(int argc, VALUE *argv, VALUE m) { rb_check_arity(argc, 10, 10); return r_disc(m, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9]); }
static VALUE v_ring(int argc, VALUE *argv, VALUE m) { rb_check_arity(argc, 11, 11); return r_ring(m, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9], argv[10]); }
static VALUE v_arc(int argc, VALUE *argv, VALUE m) { rb_check_arity(argc, 13, 13); return r_arc(m, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9], argv[10], argv[11], argv[12]); }
static VALUE v_ngon(int argc, VALUE *argv, VALUE m) { rb_check_arity(argc, 12, 12); return r_ngon(m, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9], argv[10], argv[11]); }
static VALUE v_line(int argc, VALUE *argv, VALUE m) { rb_check_arity(argc, 12, 12); return r_line(m, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9], argv[10], argv[11]); }
static VALUE v_scale(int argc, VALUE *argv, VALUE m) { rb_check_arity(argc, 8, 8); return r_scale(m, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7]); }
static VALUE v_blit_add(int argc, VALUE *argv, VALUE m) { rb_check_arity(argc, 8, 8); return r_blit_add(m, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7]); }
static VALUE v_scanlines(int argc, VALUE *argv, VALUE m) { rb_check_arity(argc, 4, 4); return r_scanlines(m, argv[0], argv[1], argv[2], argv[3]); }

void Init_yarvpilled_raster(VALUE mNative) {
  VALUE r = rb_define_module_under(mNative, "Raster");
  rb_define_module_function(r, "fill", v_fill, -1);
  rb_define_module_function(r, "rect", v_rect, -1);
  rb_define_module_function(r, "glow", v_glow, -1);
  rb_define_module_function(r, "disc", v_disc, -1);
  rb_define_module_function(r, "ring", v_ring, -1);
  rb_define_module_function(r, "arc", v_arc, -1);
  rb_define_module_function(r, "ngon", v_ngon, -1);
  rb_define_module_function(r, "line", v_line, -1);
  rb_define_module_function(r, "scale", v_scale, -1);
  rb_define_module_function(r, "text", r_text, -1);
  rb_define_module_function(r, "heat", r_heat, -1);
  rb_define_module_function(r, "blit_add", v_blit_add, -1);
  rb_define_module_function(r, "scanlines", v_scanlines, -1);
}
