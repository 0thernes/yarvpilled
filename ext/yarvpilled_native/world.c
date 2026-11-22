/*
 * world.c -- Ruby glue for the A-Life world loop (ruby.h C API only).
 *
 * The hot loop itself lives in a backend kernel that works on plain buffers:
 *   :c     kernel_c.c                         (reference)
 *   :asm   kernel_c.c + crowd_x86_64.S         (hand-written asm crowd scan)
 *   :rust  ext/yarvpilled_rust (staticlib)     (whole sense/act kernel in Rust)
 * This file converts Ruby Arrays <-> int32 buffers identically for every
 * backend, so benchmark differences come from the kernels alone.
 *
 * Thinking never happens here: every creature's decision comes from its
 * genome, a RubyVM::InstructionSequence executed by YARV.
 * lib/yarvpilled/world_ruby.rb is the bit-identical pure-Ruby port.
 */
#if defined(__linux__) && !defined(_POSIX_C_SOURCE)
#define _POSIX_C_SOURCE 199309L
#endif
#include <ruby.h>
#include <time.h>
#include <math.h>
#include <string.h>
#include <stdlib.h>
#include "world.h"
#include "trig_table.h"

static void world_free(void *p) {
  World *w = p;
  xfree(w->x); xfree(w->y); xfree(w->heading); xfree(w->age); xfree(w->species);
  xfree(w->cost); xfree(w->last_action); xfree(w->energy); xfree(w->alive);
  xfree(w->food); xfree(w->fert); xfree(w->facc); xfree(w->ghead); xfree(w->gnext);
  xfree(w->sbuf); xfree(w->abuf); xfree(w->bbuf); xfree(w->dbuf);
  xfree(w);
}

static size_t world_memsize(const void *p) {
  const World *w = p;
  return sizeof(World) + (size_t)w->cap * (2 * sizeof(double) + 9 * sizeof(int32_t) + sizeof(int64_t) + 1 + SENSORS * sizeof(int32_t)) +
         (size_t)w->fw * w->fh * 3 + (size_t)w->gw * w->gh * sizeof(int32_t);
}

static const rb_data_type_t world_type = {
  "Yarvpilled::Native::World", { NULL, world_free, world_memsize, }, 0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE world_alloc(VALUE klass) {
  World *w = ZALLOC(World);
  return TypedData_Wrap_Struct(klass, &world_type, w);
}

static World *get_world(VALUE self) {
  World *w;
  TypedData_Get_Struct(self, World, &world_type, w);
  return w;
}

static inline double wrapd(double v, double m) {
  if (v < 0) v += m;
  if (v >= m) v -= m;
  return v;
}

static inline int food_index(World *w, double x, double y) {
  int cx = (int)(x / w->fcell), cy = (int)(y / w->fcell);
  cx %= w->fw; if (cx < 0) cx += w->fw;
  cy %= w->fh; if (cy < 0) cy += w->fh;
  return cy * w->fw + cx;
}

/* World.new(width, height, food_cell, capacity, backend = :c) */
static VALUE world_init(int argc, VALUE *argv, VALUE self) {
  rb_check_arity(argc, 4, 5);
  World *w = get_world(self);
  w->w = NUM2DBL(argv[0]); w->h = NUM2DBL(argv[1]);
  w->fcell = NUM2INT(argv[2]); w->cap = NUM2INT(argv[3]);
  /* Preconditions (same checks as WorldRuby): finite size of at least 3 grid
   * cells per axis (smaller tori double-count crowding and let collision
   * pushes escape the wrap), a food cell that fits, and a sane capacity. */
  if (!(w->w >= YP_MIN_SIZE && w->w <= YP_MAX_SIZE && w->h >= YP_MIN_SIZE && w->h <= YP_MAX_SIZE))
    rb_raise(rb_eArgError, "world size must be within [%d, %d]", YP_MIN_SIZE, YP_MAX_SIZE);
  if (w->fcell <= 0 || w->fcell > YP_MIN_SIZE) rb_raise(rb_eArgError, "food cell must be in 1..%d", YP_MIN_SIZE);
  if (w->cap <= 0 || w->cap > YP_MAX_CAP) rb_raise(rb_eArgError, "capacity must be in 1..%d", YP_MAX_CAP);
  w->backend = BACKEND_C;
  if (argc == 5 && !NIL_P(argv[4])) {
    ID b = SYM2ID(argv[4]);
    if (b == rb_intern("c")) w->backend = BACKEND_C;
    else if (b == rb_intern("asm")) w->backend = BACKEND_ASM;
    else if (b == rb_intern("rust")) {
#ifdef YP_HAVE_RUST
      w->backend = BACKEND_RUST;
#else
      rb_raise(rb_eNotImpError, "built without the Rust kernel (cargo not found at build time)");
#endif
    } else rb_raise(rb_eArgError, "unknown backend");
  }
  w->fw = (int)(w->w / w->fcell); w->fh = (int)(w->h / w->fcell);
  w->gcell = 24; w->gw = (int)ceil(w->w / w->gcell); w->gh = (int)ceil(w->h / w->gcell);
  w->x = ZALLOC_N(double, w->cap); w->y = ZALLOC_N(double, w->cap);
  w->heading = ZALLOC_N(int32_t, w->cap); w->age = ZALLOC_N(int32_t, w->cap);
  w->species = ZALLOC_N(int32_t, w->cap); w->cost = ZALLOC_N(int32_t, w->cap);
  w->last_action = ZALLOC_N(int32_t, w->cap);
  w->energy = ZALLOC_N(int64_t, w->cap); w->alive = ZALLOC_N(uint8_t, w->cap);
  w->food = ZALLOC_N(uint8_t, w->fw * w->fh);
  w->fert = ZALLOC_N(uint8_t, w->fw * w->fh);
  w->facc = ZALLOC_N(uint8_t, w->fw * w->fh);
  w->ghead = ZALLOC_N(int32_t, w->gw * w->gh); w->gnext = ZALLOC_N(int32_t, w->cap);
  w->sbuf = ZALLOC_N(int32_t, (long)w->cap * SENSORS); w->abuf = ZALLOC_N(int32_t, w->cap);
  w->bbuf = ZALLOC_N(int32_t, w->cap); w->dbuf = ZALLOC_N(int32_t, w->cap);
  return self;
}

static VALUE world_backend(VALUE self) {
  static const char *names[] = { "c", "rust", "asm" };
  return ID2SYM(rb_intern(names[get_world(self)->backend]));
}

/* sense(out_array) -> alive count. out[i*6 .. i*6+5] = fa, fl, fr, en, cr, ag */
static VALUE world_sense(VALUE self, VALUE out) {
  World *w = get_world(self);
  Check_Type(out, T_ARRAY);
  int32_t alive;
#ifdef YP_HAVE_RUST
  if (w->backend == BACKEND_RUST) alive = yp_rust_sense(w, w->sbuf);
  else
#endif
  alive = yp_c_sense(w, w->sbuf);
  long n = (long)w->used * SENSORS;
  for (long k = 0; k < n; k++) rb_ary_store(out, k, INT2FIX(w->sbuf[k]));
  return INT2FIX(alive);
}

/* act(actions, birth_threshold) -> [birth_slots, death_slots] */
static VALUE world_act(VALUE self, VALUE actions, VALUE vthresh) {
  World *w = get_world(self);
  Check_Type(actions, T_ARRAY);
  int64_t thresh = NUM2LL(vthresh);
  long alen = RARRAY_LEN(actions);
  if (alen > w->used) alen = w->used;
  for (long i = 0; i < alen; i++) w->abuf[i] = (int32_t)(NUM2LONG(RARRAY_AREF(actions, i)) & 3);
  int32_t nb = 0, nd = 0;
#ifdef YP_HAVE_RUST
  if (w->backend == BACKEND_RUST) yp_rust_act(w, w->abuf, alen, thresh, w->bbuf, &nb, w->dbuf, &nd);
  else
#endif
  yp_c_act(w, w->abuf, alen, thresh, w->bbuf, &nb, w->dbuf, &nd);
  VALUE births = rb_ary_new_capa(nb), deaths = rb_ary_new_capa(nd);
  for (int k = 0; k < nb; k++) rb_ary_push(births, INT2FIX(w->bbuf[k]));
  for (int k = 0; k < nd; k++) rb_ary_push(deaths, INT2FIX(w->dbuf[k]));
  return rb_assoc_new(births, deaths);
}

static double now_sec(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return ts.tv_sec + ts.tv_nsec * 1e-9;
}

/* kernel_bench(iters) -> [sense_sec, act_sec, crowd_sec_or_nil, updates]
 * Times the backend kernels alone, with no Ruby Array glue, on this world
 * (mutates it). crowd_sec isolates the crowd-sensing scan (C or asm); the
 * Rust kernel inlines its scan, so it reports nil there. */
static VALUE world_kernel_bench(VALUE self, VALUE viters) {
  World *w = get_world(self);
  int n = NUM2INT(viters);
  for (int i = 0; i < w->used; i++) w->abuf[i] = i & 3;
  double ts = 0, ta = 0, tc = 0;
  long updates = 0, sink = 0;
  for (int it = 0; it < n; it++) {
    int32_t nb, nd, alive;
    double t0 = now_sec();
#ifdef YP_HAVE_RUST
    if (w->backend == BACKEND_RUST) alive = yp_rust_sense(w, w->sbuf); else
#endif
    alive = yp_c_sense(w, w->sbuf);
    double t1 = now_sec();
#ifdef YP_HAVE_RUST
    if (w->backend == BACKEND_RUST) yp_rust_act(w, w->abuf, w->used, INT64_MAX, w->bbuf, &nb, w->dbuf, &nd); else
#endif
    yp_c_act(w, w->abuf, w->used, INT64_MAX, w->bbuf, &nb, w->dbuf, &nd);
    double t2 = now_sec();
    ts += t1 - t0; ta += t2 - t1; updates += alive;
    if (w->backend != BACKEND_RUST) {
      yp_build_grid(w);
      CrowdCtx ctx = { w->x, w->y, w->ghead, w->gnext, w->gw, w->gh, (double)w->gcell, w->w, w->h, CROWD_R * CROWD_R };
      int32_t (*crowd)(const CrowdCtx *, int32_t) = w->backend == BACKEND_ASM ? yp_asm_crowd : yp_c_crowd;
      double t3 = now_sec();
      for (int i = 0; i < w->used; i++) if (w->alive[i]) sink += crowd(&ctx, i);
      tc += now_sec() - t3;
    }
  }
  (void)sink;
  return rb_ary_new_from_args(4, DBL2NUM(ts), DBL2NUM(ta), w->backend == BACKEND_RUST ? Qnil : DBL2NUM(tc), LONG2NUM(updates));
}

/* spawn(x, y, heading, energy, species_id, cost) -> slot */
static VALUE world_spawn(VALUE self, VALUE vx, VALUE vy, VALUE vh, VALUE ve, VALUE vs, VALUE vc) {
  World *w = get_world(self);
  double px = NUM2DBL(vx), py = NUM2DBL(vy);
  /* one wrap step must land inside the torus (rejects NaN/inf and far-away points) */
  if (!(px >= -w->w && px < 2 * w->w && py >= -w->h && py < 2 * w->h))
    rb_raise(rb_eArgError, "spawn position out of range");
  int slot = -1;
  for (int i = 0; i < w->used; i++) if (!w->alive[i]) { slot = i; break; }
  if (slot < 0) {
    if (w->used >= w->cap) return Qnil;
    slot = w->used++;
  }
  w->x[slot] = wrapd(px, w->w); w->y[slot] = wrapd(py, w->h);
  w->heading[slot] = NUM2INT(vh) & (NDIR - 1);
  w->energy[slot] = NUM2LONG(ve); w->species[slot] = NUM2INT(vs); w->cost[slot] = NUM2INT(vc);
  w->age[slot] = 0; w->alive[slot] = 1; w->last_action[slot] = 0;
  return INT2FIX(slot);
}

static VALUE world_spawn_v(int argc, VALUE *argv, VALUE self) {
  rb_check_arity(argc, 6, 6); /* variadic: see YJIT note in raster.c */
  return world_spawn(self, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5]);
}

/* split(slot) -> energy handed to the child (parent keeps half) */
static VALUE world_split(VALUE self, VALUE vi) {
  World *w = get_world(self);
  int i = NUM2INT(vi);
  if (i < 0 || i >= w->used || !w->alive[i]) return INT2FIX(0);
  long half = w->energy[i] / 2;
  w->energy[i] -= half;
  return LONG2NUM(half - 20);
}

static VALUE world_feed(VALUE self, VALUE vi, VALUE amt) {
  World *w = get_world(self);
  int i = NUM2INT(vi);
  if (i >= 0 && i < w->used && w->alive[i]) w->energy[i] += NUM2LONG(amt);
  return Qnil;
}

static VALUE world_set_species(VALUE self, VALUE vi, VALUE vs, VALUE vc) {
  World *w = get_world(self);
  int i = NUM2INT(vi);
  if (i >= 0 && i < w->used) { w->species[i] = NUM2INT(vs); w->cost[i] = NUM2INT(vc); }
  return Qnil;
}

static VALUE world_set_fertility(VALUE self, VALUE str) {
  World *w = get_world(self);
  StringValue(str);
  if (RSTRING_LEN(str) != w->fw * w->fh) rb_raise(rb_eArgError, "fertility must be %d bytes", w->fw * w->fh);
  memcpy(w->fert, RSTRING_PTR(str), (size_t)(w->fw * w->fh));
  return Qnil;
}

static VALUE world_fill_food(VALUE self, VALUE v) {
  World *w = get_world(self);
  memset(w->food, NUM2INT(v) & 255, (size_t)(w->fw * w->fh));
  return Qnil;
}

static VALUE world_food_bytes(VALUE self) {
  World *w = get_world(self);
  return rb_str_new((const char *)w->food, w->fw * w->fh);
}

/* snapshot -> flat [slot, x, y, heading, energy, species, age, action]* (alive only) */
static VALUE world_snapshot(VALUE self) {
  World *w = get_world(self);
  VALUE out = rb_ary_new_capa(w->used * 8);
  for (int i = 0; i < w->used; i++) {
    if (!w->alive[i]) continue;
    rb_ary_push(out, INT2FIX(i));
    rb_ary_push(out, DBL2NUM(w->x[i]));
    rb_ary_push(out, DBL2NUM(w->y[i]));
    rb_ary_push(out, INT2FIX(w->heading[i]));
    rb_ary_push(out, LONG2NUM(w->energy[i]));
    rb_ary_push(out, INT2FIX(w->species[i]));
    rb_ary_push(out, INT2FIX(w->age[i]));
    rb_ary_push(out, INT2FIX(w->last_action[i]));
  }
  return out;
}

static VALUE world_species_of(VALUE self, VALUE vi) { return INT2FIX(get_world(self)->species[NUM2INT(vi)]); }
static VALUE world_alive_p(VALUE self, VALUE vi) {
  World *w = get_world(self); int i = NUM2INT(vi);
  return (i >= 0 && i < w->used && w->alive[i]) ? Qtrue : Qfalse;
}
static VALUE world_used(VALUE self) { return INT2FIX(get_world(self)->used); }
static VALUE world_food_dims(VALUE self) { World *w = get_world(self); return rb_ary_new_from_args(3, INT2FIX(w->fw), INT2FIX(w->fh), INT2FIX(w->fcell)); }
static VALUE world_stats(VALUE self) {
  World *w = get_world(self);
  VALUE h = rb_hash_new();
  int alive = 0; for (int i = 0; i < w->used; i++) alive += w->alive[i];
  long food = 0; for (int c = 0; c < w->fw * w->fh; c++) food += w->food[c];
  rb_hash_aset(h, ID2SYM(rb_intern("alive")), INT2FIX(alive));
  rb_hash_aset(h, ID2SYM(rb_intern("food")), LONG2NUM(food));
  rb_hash_aset(h, ID2SYM(rb_intern("eaten")), LONG2NUM(w->eaten_total));
  rb_hash_aset(h, ID2SYM(rb_intern("deaths")), LONG2NUM(w->deaths_total));
  rb_hash_aset(h, ID2SYM(rb_intern("ticks")), LONG2NUM(w->ticks));
  return h;
}

void Init_yarvpilled_world(VALUE mNative) {
  /* Directions come from literal IEEE-754 bit patterns, not the platform libm. */
  memcpy(yp_cos_t, YP_COS_BITS, sizeof yp_cos_t);
  memcpy(yp_sin_t, YP_SIN_BITS, sizeof yp_sin_t);
  VALUE c = rb_define_class_under(mNative, "World", rb_cObject);
  rb_define_alloc_func(c, world_alloc);
  rb_define_method(c, "initialize", world_init, -1);
  rb_define_method(c, "backend", world_backend, 0);
  rb_define_method(c, "kernel_bench", world_kernel_bench, 1);
  rb_define_method(c, "sense", world_sense, 1);
  rb_define_method(c, "act", world_act, 2);
  rb_define_method(c, "spawn", world_spawn_v, -1);
  rb_define_method(c, "split", world_split, 1);
  rb_define_method(c, "feed", world_feed, 2);
  rb_define_method(c, "set_species", world_set_species, 3);
  rb_define_method(c, "fertility=", world_set_fertility, 1);
  rb_define_method(c, "fill_food", world_fill_food, 1);
  rb_define_method(c, "food_bytes", world_food_bytes, 0);
  rb_define_method(c, "snapshot", world_snapshot, 0);
  rb_define_method(c, "species_of", world_species_of, 1);
  rb_define_method(c, "alive?", world_alive_p, 1);
  rb_define_method(c, "used", world_used, 0);
  rb_define_method(c, "food_dims", world_food_dims, 0);
  rb_define_method(c, "stats", world_stats, 0);
}
