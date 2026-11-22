//! Rust port of ext/yarvpilled_native/kernel_c.c: the A-Life world loop
//! (food regrowth, sensing with spatial-hash crowd scan, movement, eating,
//! metabolism, collision, death). No dependencies; plain C ABI. It operates
//! in place on the C-owned `World` struct, so the Ruby glue is shared with
//! the C and asm backends and the work is bit-for-bit identical.
#![allow(clippy::missing_safety_doc)]

const NDIR: i32 = 64;
const SENSORS: usize = 6;
const RADIUS: f64 = 4.0;
const CROWD_R: f64 = 20.0;
const MAX_AGE: i32 = 900;
const FOOD_MAX: i32 = 255;

/// Mirror of `World` in ext/yarvpilled_native/world.h (field order matters).
#[repr(C)]
pub struct World {
    cap: i32,
    used: i32,
    w: f64,
    h: f64,
    x: *mut f64,
    y: *mut f64,
    heading: *mut i32,
    age: *mut i32,
    species: *mut i32,
    cost: *mut i32,
    last_action: *mut i32,
    energy: *mut i64,
    alive: *mut u8,
    fw: i32,
    fh: i32,
    fcell: i32,
    food: *mut u8,
    fert: *mut u8,
    facc: *mut u8,
    gw: i32,
    gh: i32,
    gcell: i32,
    ghead: *mut i32,
    gnext: *mut i32,
    eaten_total: i64,
    ticks: i64,
    deaths_total: i64,
    backend: i32,
    sbuf: *mut i32,
    abuf: *mut i32,
    bbuf: *mut i32,
    dbuf: *mut i32,
}

mod trig_table;

/// Direction tables from literal IEEE-754 bits (same bits as the C and Ruby tables).
const fn table(bits: &[u64; 64]) -> [f64; 64] {
    let mut out = [0.0; 64];
    let mut k = 0;
    while k < 64 {
        out[k] = f64::from_bits(bits[k]);
        k += 1;
    }
    out
}
static COS_T: [f64; 64] = table(&trig_table::COS_BITS);
static SIN_T: [f64; 64] = table(&trig_table::SIN_BITS);

// ---- Small pure pieces of the step, shared by the kernel and the Kani proofs ----

/// Food regrowth for one cell: returns (food', facc').
#[inline(always)]
pub(crate) fn regrow(food: u8, facc: u8, fert: u8) -> (u8, u8) {
    let acc = facc as i32 + fert as i32;
    let f = food as i32 + (acc >> 8);
    (f.min(FOOD_MAX) as u8, (acc & 255) as u8)
}

/// Eating from one cell: returns (food', take). Grazing (action 0) bites 9, moving bites 4.
#[inline(always)]
pub(crate) fn eat(food: u8, action: i32) -> (u8, i32) {
    let bite = if action == 0 { 9 } else { 4 };
    let take = (food as i32).min(bite);
    (food - take as u8, take)
}

/// Energy after eating `take` and paying metabolism (computed in i64: no i32 overflow for any cost).
#[inline(always)]
pub(crate) fn metabolize(energy: i64, take: i32, cost: i32, action: i32) -> i64 {
    energy + (take + take / 2) as i64 - (3 + cost as i64 + if action == 3 { 3 } else { 0 })
}

/// Toroidal grid neighbour index: (g + o + n) % n for g in [0, n), o in {-1, 0, 1}.
#[inline(always)]
pub(crate) fn grid_wrap(g: i32, o: i32, n: i32) -> i32 {
    (g + o + n) % n
}

/// Energy sensor: energy / 4 clamped to [0, 255].
#[inline(always)]
pub(crate) fn sense_energy(e: i64) -> i32 {
    (e / 4).clamp(0, 255) as i32
}

/// Borrowed slice views of the C-owned buffers for one kernel call.
struct V<'a> {
    w: f64,
    h: f64,
    used: usize,
    x: &'a mut [f64],
    y: &'a mut [f64],
    heading: &'a mut [i32],
    age: &'a mut [i32],
    cost: &'a [i32],
    last_action: &'a mut [i32],
    energy: &'a mut [i64],
    alive: &'a mut [u8],
    fw: i32,
    fh: i32,
    fcell: i32,
    food: &'a mut [u8],
    fert: &'a [u8],
    facc: &'a mut [u8],
    gw: i32,
    gh: i32,
    gcell: i32,
    ghead: &'a mut [i32],
    gnext: &'a mut [i32],
}

unsafe fn view(w: &mut World) -> V<'_> {
    use std::slice::from_raw_parts_mut as sm;
    let cap = w.cap as usize;
    let nf = (w.fw * w.fh) as usize;
    let ng = (w.gw * w.gh) as usize;
    V {
        w: w.w,
        h: w.h,
        used: w.used as usize,
        x: sm(w.x, cap),
        y: sm(w.y, cap),
        heading: sm(w.heading, cap),
        age: sm(w.age, cap),
        cost: sm(w.cost, cap),
        last_action: sm(w.last_action, cap),
        energy: sm(w.energy, cap),
        alive: sm(w.alive, cap),
        fw: w.fw,
        fh: w.fh,
        fcell: w.fcell,
        food: sm(w.food, nf),
        fert: sm(w.fert, nf),
        facc: sm(w.facc, nf),
        gw: w.gw,
        gh: w.gh,
        gcell: w.gcell,
        ghead: sm(w.ghead, ng),
        gnext: sm(w.gnext, cap),
    }
}

#[inline(always)]
fn food_index(v: &V, x: f64, y: f64) -> usize {
    let mut cx = (x / v.fcell as f64) as i32;
    let mut cy = (y / v.fcell as f64) as i32;
    cx %= v.fw;
    if cx < 0 {
        cx += v.fw;
    }
    cy %= v.fh;
    if cy < 0 {
        cy += v.fh;
    }
    (cy * v.fw + cx) as usize
}

#[inline(always)]
fn wrapd(mut val: f64, m: f64) -> f64 {
    if val < 0.0 {
        val += m;
    }
    if val >= m {
        val -= m;
    }
    val
}

#[inline(always)]
fn tdelta(a: f64, b: f64, m: f64) -> f64 {
    let mut d = b - a;
    if d > m / 2.0 {
        d -= m;
    }
    if d < -m / 2.0 {
        d += m;
    }
    d
}

fn build_grid(v: &mut V) {
    v.ghead.fill(-1);
    for i in 0..v.used {
        if v.alive[i] == 0 {
            continue;
        }
        let gx = (v.x[i] / v.gcell as f64) as i32 % v.gw;
        let gy = (v.y[i] / v.gcell as f64) as i32 % v.gh;
        let c = (gy * v.gw + gx) as usize;
        v.gnext[i] = v.ghead[c];
        v.ghead[c] = i as i32;
    }
}

#[no_mangle]
pub unsafe extern "C" fn yp_rust_sense(wp: *mut World, out: *mut i32) -> i32 {
    let w = &mut *wp;
    let mut v = view(w);
    let out = std::slice::from_raw_parts_mut(out, v.x.len() * SENSORS);
    let (cos_t, sin_t) = (&COS_T, &SIN_T);
    build_grid(&mut v);
    let r2 = CROWD_R * CROWD_R;
    let gcell = v.gcell as f64;
    let mut alive = 0;
    for i in 0..v.used {
        let o = &mut out[i * SENSORS..i * SENSORS + SENSORS];
        if v.alive[i] == 0 {
            o.fill(0);
            continue;
        }
        alive += 1;
        let h = v.heading[i] as usize;
        let hl = ((h as i32 - 6) & (NDIR - 1)) as usize;
        let hr = ((h as i32 + 6) & (NDIR - 1)) as usize;
        let (px, py) = (v.x[i], v.y[i]);
        o[0] = v.food[food_index(&v, px + cos_t[h] * 10.0, py + sin_t[h] * 10.0)] as i32;
        o[1] = v.food[food_index(&v, px + cos_t[hl] * 10.0, py + sin_t[hl] * 10.0)] as i32;
        o[2] = v.food[food_index(&v, px + cos_t[hr] * 10.0, py + sin_t[hr] * 10.0)] as i32;
        o[3] = sense_energy(v.energy[i]);
        let gx = (px / gcell) as i32;
        let gy = (py / gcell) as i32;
        let mut cr = 0;
        for oy in -1..=1 {
            for ox in -1..=1 {
                let cx = grid_wrap(gx, ox, v.gw);
                let cy = grid_wrap(gy, oy, v.gh);
                let mut j = v.ghead[(cy * v.gw + cx) as usize];
                while j >= 0 {
                    let ju = j as usize;
                    if ju != i {
                        let dx = tdelta(px, v.x[ju], v.w);
                        let dy = tdelta(py, v.y[ju], v.h);
                        if dx * dx + dy * dy < r2 {
                            cr += 1;
                        }
                    }
                    j = v.gnext[ju];
                }
            }
        }
        o[4] = cr.min(15);
        o[5] = (v.age[i] / 8).min(255);
    }
    alive
}

#[no_mangle]
#[allow(clippy::needless_range_loop)] // index-parallel arrays, mirrors kernel_c.c line for line
pub unsafe extern "C" fn yp_rust_act(
    wp: *mut World,
    actions: *const i32,
    alen: i64,
    thresh: i64,
    births: *mut i32,
    nb: *mut i32,
    deaths: *mut i32,
    nd: *mut i32,
) {
    let w = &mut *wp;
    let (mut eaten, mut deaths_total) = (0i64, 0i64);
    {
        let mut v = view(w);
        let actions = std::slice::from_raw_parts(actions, alen.max(0) as usize);
        let births = std::slice::from_raw_parts_mut(births, v.x.len());
        let deaths = std::slice::from_raw_parts_mut(deaths, v.x.len());
        let (cos_t, sin_t) = (&COS_T, &SIN_T);
        let (mut b, mut d) = (0usize, 0usize);

        for c in 0..v.food.len() {
            (v.food[c], v.facc[c]) = regrow(v.food[c], v.facc[c], v.fert[c]);
        }
        for i in 0..v.used {
            if v.alive[i] == 0 {
                continue;
            }
            let a = if (i as i64) < alen { actions[i] & 3 } else { 0 };
            v.last_action[i] = a;
            let speed = match a {
                0 => 0.35,
                1 => {
                    v.heading[i] = (v.heading[i] - 3) & (NDIR - 1);
                    1.0
                }
                2 => {
                    v.heading[i] = (v.heading[i] + 3) & (NDIR - 1);
                    1.0
                }
                _ => 2.4,
            };
            let h = v.heading[i] as usize;
            v.x[i] = wrapd(v.x[i] + cos_t[h] * speed, v.w);
            v.y[i] = wrapd(v.y[i] + sin_t[h] * speed, v.h);
            let fc = food_index(&v, v.x[i], v.y[i]);
            let take;
            (v.food[fc], take) = eat(v.food[fc], a);
            eaten += take as i64;
            v.energy[i] = metabolize(v.energy[i], take, v.cost[i], a);
            v.age[i] += 1;
        }
        build_grid(&mut v);
        let lim = (2.0 * RADIUS) * (2.0 * RADIUS);
        let gcell = v.gcell as f64;
        for i in 0..v.used {
            if v.alive[i] == 0 {
                continue;
            }
            let gx = (v.x[i] / gcell) as i32;
            let gy = (v.y[i] / gcell) as i32;
            for oy in -1..=1 {
                for ox in -1..=1 {
                    let cx = grid_wrap(gx, ox, v.gw);
                    let cy = grid_wrap(gy, oy, v.gh);
                    let mut j = v.ghead[(cy * v.gw + cx) as usize];
                    while j >= 0 {
                        let ju = j as usize;
                        if ju > i {
                            let dx = tdelta(v.x[i], v.x[ju], v.w);
                            let dy = tdelta(v.y[i], v.y[ju], v.h);
                            let d2 = dx * dx + dy * dy;
                            if d2 < lim && d2 != 0.0 {
                                let dd = d2.sqrt();
                                let push = (2.0 * RADIUS - dd) * 0.5 / dd;
                                v.x[i] = wrapd(v.x[i] - dx * push, v.w);
                                v.y[i] = wrapd(v.y[i] - dy * push, v.h);
                                v.x[ju] = wrapd(v.x[ju] + dx * push, v.w);
                                v.y[ju] = wrapd(v.y[ju] + dy * push, v.h);
                            }
                        }
                        j = v.gnext[ju];
                    }
                }
            }
        }
        for i in 0..v.used {
            if v.alive[i] == 0 {
                continue;
            }
            if v.energy[i] <= 0 || v.age[i] >= MAX_AGE {
                v.alive[i] = 0;
                let fc = food_index(&v, v.x[i], v.y[i]);
                v.food[fc] = (v.food[fc] as i32 + 40).min(FOOD_MAX) as u8;
                deaths_total += 1;
                deaths[d] = i as i32;
                d += 1;
            } else if v.energy[i] >= thresh {
                births[b] = i as i32;
                b += 1;
            }
        }
        *nb = b as i32;
        *nd = d as i32;
    }
    w.eaten_total += eaten;
    w.deaths_total += deaths_total;
    w.ticks += 1;
}

#[cfg(any(kani, feature = "proof-check"))]
mod proofs;
