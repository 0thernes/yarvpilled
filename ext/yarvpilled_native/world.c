/*
 * world.c -- the hot A-Life world loop for YARVPILLED, written against the
 * plain CRuby C API (ruby.h). Spatial hash grid, food/resource field,
 * movement, eating, metabolism, collision and death all happen here.
 *
 * What does NOT happen here: thinking. Every creature's decision is made by
 * its genome, a real RubyVM::InstructionSequence executed by YARV. Ruby asks
 * this file for sensor values (sense), runs the bytecode, and hands the
 * resulting actions back (act).
 *
 * lib/yarvpilled/world_ruby.rb is a line-for-line pure-Ruby port with the
 * identical arithmetic so the two tiers are bit-for-bit comparable
 * (test/test_world_equivalence.rb checks this).
 */
#include <ruby.h>
#include <math.h>
#include <string.h>
#include <stdlib.h>

#define NDIR 64
#define SENSORS 6
#define RADIUS 4.0
#define CROWD_R 20.0
#define MAX_AGE 900
#define FOOD_MAX 255

typedef struct {
  int cap, used;               /* slots allocated / high-water mark */
  double w, h;                 /* world size in world units */
  double *x, *y;
  int *heading, *age, *species, *cost, *last_action;
  long *energy;
  unsigned char *alive;
  int fw, fh, fcell;           /* food grid */
  unsigned char *food, *fert, *facc;
  int gw, gh, gcell;           /* spatial hash */
  int *ghead, *gnext;
  long eaten_total, ticks, deaths_total;
} World;

static double COS_T[NDIR], SIN_T[NDIR];

static void world_free(void *p) {
  World *w = p;
  xfree(w->x); xfree(w->y); xfree(w->heading); xfree(w->age); xfree(w->species);
  xfree(w->cost); xfree(w->last_action); xfree(w->energy); xfree(w->alive);
  xfree(w->food); xfree(w->fert); xfree(w->facc); xfree(w->ghead); xfree(w->gnext);
  xfree(w);
}

static size_t world_memsize(const void *p) {
  const World *w = p;
  return sizeof(World) + (size_t)w->cap * (2 * sizeof(double) + 5 * sizeof(int) + sizeof(long) + 1 + sizeof(int)) +
         (size_t)w->fw * w->fh * 3 + (size_t)w->gw * w->gh * sizeof(int);
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

/* World.new(width, height, food_cell, capacity) */
static VALUE world_init(VALUE self, VALUE vw, VALUE vh, VALUE vcell, VALUE vcap) {
  World *w = get_world(self);
  w->w = NUM2DBL(vw); w->h = NUM2DBL(vh);
  w->fcell = NUM2INT(vcell); w->cap = NUM2INT(vcap);
  if (w->fcell <= 0 || w->cap <= 0) rb_raise(rb_eArgError, "bad world params");
  w->fw = (int)(w->w / w->fcell); w->fh = (int)(w->h / w->fcell);
  w->gcell = 24; w->gw = (int)ceil(w->w / w->gcell); w->gh = (int)ceil(w->h / w->gcell);
  w->x = ZALLOC_N(double, w->cap); w->y = ZALLOC_N(double, w->cap);
  w->heading = ZALLOC_N(int, w->cap); w->age = ZALLOC_N(int, w->cap);
  w->species = ZALLOC_N(int, w->cap); w->cost = ZALLOC_N(int, w->cap);
  w->last_action = ZALLOC_N(int, w->cap);
  w->energy = ZALLOC_N(long, w->cap); w->alive = ZALLOC_N(unsigned char, w->cap);
  w->food = ZALLOC_N(unsigned char, w->fw * w->fh);
  w->fert = ZALLOC_N(unsigned char, w->fw * w->fh);
  w->facc = ZALLOC_N(unsigned char, w->fw * w->fh);
  w->ghead = ZALLOC_N(int, w->gw * w->gh); w->gnext = ZALLOC_N(int, w->cap);
  return self;
}

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

static void build_grid(World *w) {
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

/* sense(out_array) -> alive count. out[i*6 .. i*6+5] = fa, fl, fr, en, cr, ag */
static VALUE world_sense(VALUE self, VALUE out) {
  World *w = get_world(self);
  Check_Type(out, T_ARRAY);
  build_grid(w);
  int alive = 0;
  for (int i = 0; i < w->used; i++) {
    long base = (long)i * SENSORS;
    if (!w->alive[i]) {
      for (int k = 0; k < SENSORS; k++) rb_ary_store(out, base + k, INT2FIX(0));
      continue;
    }
    alive++;
    int h = w->heading[i];
    int hl = (h - 6) & (NDIR - 1), hr = (h + 6) & (NDIR - 1);
    double px = w->x[i], py = w->y[i];
    int fa = w->food[food_index(w, px + COS_T[h] * 10.0, py + SIN_T[h] * 10.0)];
    int fl = w->food[food_index(w, px + COS_T[hl] * 10.0, py + SIN_T[hl] * 10.0)];
    int fr = w->food[food_index(w, px + COS_T[hr] * 10.0, py + SIN_T[hr] * 10.0)];
    long en = w->energy[i] / 4; if (en > 255) en = 255; if (en < 0) en = 0;
    int ag = w->age[i] / 8; if (ag > 255) ag = 255;
    int cr = 0;
    int gx = (int)(px / w->gcell), gy = (int)(py / w->gcell);
    for (int oy = -1; oy <= 1; oy++) for (int ox = -1; ox <= 1; ox++) {
      int cx = (gx + ox + w->gw) % w->gw, cy = (gy + oy + w->gh) % w->gh;
      for (int j = w->ghead[cy * w->gw + cx]; j >= 0; j = w->gnext[j]) {
        if (j == i) continue;
        double dx = tdelta(px, w->x[j], w->w), dy = tdelta(py, w->y[j], w->h);
        if (dx * dx + dy * dy < CROWD_R * CROWD_R) cr++;
      }
    }
    if (cr > 15) cr = 15;
    rb_ary_store(out, base + 0, INT2FIX(fa));
    rb_ary_store(out, base + 1, INT2FIX(fl));
    rb_ary_store(out, base + 2, INT2FIX(fr));
    rb_ary_store(out, base + 3, LONG2FIX(en));
    rb_ary_store(out, base + 4, INT2FIX(cr));
    rb_ary_store(out, base + 5, INT2FIX(ag));
  }
  return INT2FIX(alive);
}

/* act(actions, birth_threshold) -> [birth_slots, death_slots] */
static VALUE world_act(VALUE self, VALUE actions, VALUE vthresh) {
  World *w = get_world(self);
  Check_Type(actions, T_ARRAY);
  long thresh = NUM2LONG(vthresh);
  VALUE births = rb_ary_new(), deaths = rb_ary_new();
  long alen = RARRAY_LEN(actions);
  int nf = w->fw * w->fh;

  /* 1. resource field regrowth: integer accumulator, exact in both tiers */
  for (int c = 0; c < nf; c++) {
    int acc = w->facc[c] + w->fert[c];
    int f = w->food[c] + (acc >> 8);
    w->facc[c] = (unsigned char)(acc & 255);
    w->food[c] = (unsigned char)(f > FOOD_MAX ? FOOD_MAX : f);
  }

  /* 2. move, eat, metabolise, age */
  for (int i = 0; i < w->used; i++) {
    if (!w->alive[i]) continue;
    int a = i < alen ? (int)(NUM2LONG(RARRAY_AREF(actions, i)) & 3) : 0;
    w->last_action[i] = a;
    double speed;
    switch (a) {
      case 0: speed = 0.35; break;
      case 1: w->heading[i] = (w->heading[i] - 3) & (NDIR - 1); speed = 1.0; break;
      case 2: w->heading[i] = (w->heading[i] + 3) & (NDIR - 1); speed = 1.0; break;
      default: speed = 2.4; break;
    }
    int h = w->heading[i];
    w->x[i] = wrapd(w->x[i] + COS_T[h] * speed, w->w);
    w->y[i] = wrapd(w->y[i] + SIN_T[h] * speed, w->h);
    int fc = food_index(w, w->x[i], w->y[i]);
    int bite = a == 0 ? 9 : 4;
    int take = w->food[fc] < bite ? w->food[fc] : bite;
    w->food[fc] -= take;
    w->eaten_total += take;
    w->energy[i] += take + take / 2;
    w->energy[i] -= 3 + w->cost[i] + (a == 3 ? 3 : 0);
    w->age[i]++;
  }

  /* 3. collision: push overlapping bodies apart (pairs i<j, grid order) */
  build_grid(w);
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

  /* 4. death (corpse returns nutrients) and birth candidates */
  for (int i = 0; i < w->used; i++) {
    if (!w->alive[i]) continue;
    if (w->energy[i] <= 0 || w->age[i] >= MAX_AGE) {
      w->alive[i] = 0;
      int fc = food_index(w, w->x[i], w->y[i]);
      int f = w->food[fc] + 40;
      w->food[fc] = (unsigned char)(f > FOOD_MAX ? FOOD_MAX : f);
      w->deaths_total++;
      rb_ary_push(deaths, INT2FIX(i));
    } else if (w->energy[i] >= thresh) {
      rb_ary_push(births, INT2FIX(i));
    }
  }
  w->ticks++;
  return rb_assoc_new(births, deaths);
}

/* spawn(x, y, heading, energy, species_id, cost) -> slot */
static VALUE world_spawn(VALUE self, VALUE vx, VALUE vy, VALUE vh, VALUE ve, VALUE vs, VALUE vc) {
  World *w = get_world(self);
  int slot = -1;
  for (int i = 0; i < w->used; i++) if (!w->alive[i]) { slot = i; break; }
  if (slot < 0) {
    if (w->used >= w->cap) return Qnil;
    slot = w->used++;
  }
  w->x[slot] = wrapd(NUM2DBL(vx), w->w); w->y[slot] = wrapd(NUM2DBL(vy), w->h);
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
  for (int k = 0; k < NDIR; k++) { COS_T[k] = cos(2.0 * M_PI * k / 64.0); SIN_T[k] = sin(2.0 * M_PI * k / 64.0); }
  VALUE c = rb_define_class_under(mNative, "World", rb_cObject);
  rb_define_alloc_func(c, world_alloc);
  rb_define_method(c, "initialize", world_init, 4);
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
