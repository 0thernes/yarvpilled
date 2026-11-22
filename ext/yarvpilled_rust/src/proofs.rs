//! Kani proof harnesses for the Rust world kernel.
//!
//! * `cargo kani` (Kani verifier): each `#[kani::proof]` is a bounded model-checking
//!   proof over *all* inputs allowed by the `any_*` helpers (no panics, no
//!   arithmetic overflow, no out-of-bounds access, plus the stated assertions).
//! * `cargo test --features proof-check` (stable Rust): the same harness bodies run
//!   as randomized tests, `RUNS` times each, with values drawn from the same ranges.
//!
//! The pure helpers below (`regrow`, `eat`, `metabolize`, `grid_wrap`,
//! `sense_energy`) are exactly the functions the kernel calls.

#![allow(dead_code)] // harnesses are entry points for Kani and the randomized tests

use super::*;

// ---------------------------------------------------------------- inputs
#[cfg(kani)]
mod gen {
    pub fn u8_any() -> u8 { kani::any() }
    pub fn i32_any() -> i32 { kani::any() }
    pub fn i32_in(lo: i32, hi: i32) -> i32 { let v: i32 = kani::any(); kani::assume(v >= lo && v <= hi); v }
    pub fn i64_in(lo: i64, hi: i64) -> i64 { let v: i64 = kani::any(); kani::assume(v >= lo && v <= hi); v }
    pub fn f64_in(lo: f64, hi: f64) -> f64 { let v: f64 = kani::any(); kani::assume(v.is_finite() && v >= lo && v < hi); v }
    pub fn bool_any() -> bool { kani::any() }
}

#[cfg(all(not(kani), feature = "proof-check"))]
mod gen {
    use std::cell::Cell;
    thread_local!(static S: Cell<u64> = const { Cell::new(0x9E37_79B9_7F4A_7C15) });
    pub fn seed(s: u64) { S.with(|c| c.set(s | 1)); }
    fn next() -> u64 {
        S.with(|c| { let mut x = c.get(); x ^= x << 13; x ^= x >> 7; x ^= x << 17; c.set(x); x })
    }
    pub fn u8_any() -> u8 { next() as u8 }
    pub fn i32_any() -> i32 {
        // bias towards edge values so overflow paths are exercised
        match next() % 8 { 0 => i32::MAX, 1 => i32::MIN, 2 => 0, _ => next() as i32 }
    }
    pub fn i32_in(lo: i32, hi: i32) -> i32 { (lo as i64 + (next() % ((hi as i64 - lo as i64 + 1) as u64)) as i64) as i32 }
    pub fn i64_in(lo: i64, hi: i64) -> i64 { (lo as i128 + (next() as u128 % ((hi as i128 - lo as i128 + 1) as u128)) as i128) as i64 }
    pub fn f64_in(lo: f64, hi: f64) -> f64 {
        let v = lo + (next() >> 11) as f64 / (1u64 << 53) as f64 * (hi - lo);
        if v >= hi { lo } else { v }
    }
    pub fn bool_any() -> bool { next() & 1 == 1 }
}

use gen::*;

const E_BOUND: i64 = 1 << 40; // energies far beyond anything the simulation reaches

// ---------------------------------------------------------------- harnesses

/// Regrowth keeps food in [0, 255], the accumulator below 256, and is exact (no loss) below the cap.
#[cfg_attr(kani, kani::proof)]
pub fn regrow_bounded_and_exact() {
    let (food, facc, fert) = (u8_any(), u8_any(), u8_any());
    let (f2, a2) = regrow(food, facc, fert);
    let total = facc as u32 + fert as u32;
    assert_eq!(a2 as u32, total % 256);
    if food as u32 + total / 256 <= 255 {
        assert_eq!(f2 as u32, food as u32 + total / 256);
    } else {
        assert_eq!(f2, 255);
    }
}

/// Eating conserves food: food' + take = food, 0 <= take <= bite.
#[cfg_attr(kani, kani::proof)]
pub fn eat_conserves_food() {
    let food = u8_any();
    let a = i32_in(0, 3);
    let (f2, take) = eat(food, a);
    assert!(take >= 0 && take <= if a == 0 { 9 } else { 4 });
    assert_eq!(f2 as i32 + take, food as i32);
}

/// Energy accounting identity, with no overflow for ANY i32 metabolic cost.
#[cfg_attr(kani, kani::proof)]
pub fn metabolize_identity_no_overflow() {
    let e = i64_in(-E_BOUND, E_BOUND);
    let take = i32_in(0, 9);
    let cost = i32_any();
    let a = i32_in(0, 3);
    let e2 = metabolize(e, take, cost, a);
    let expect = e as i128 + take as i128 + (take / 2) as i128 - 3 - cost as i128 - if a == 3 { 3 } else { 0 };
    assert_eq!(e2 as i128, expect);
}

/// Grid neighbour wrap stays in bounds and equals the cmov formulation used by crowd_x86_64.S.
#[cfg_attr(kani, kani::proof)]
pub fn grid_wrap_in_bounds_matches_asm() {
    let n = i32_in(1, 1 << 20);
    let g = i32_in(0, n - 1);
    let o = i32_in(-1, 1);
    let r = grid_wrap(g, o, n);
    assert!(r >= 0 && r < n);
    let t = g + o; // the asm: t in [-1, n]; add n if t < 0, subtract n if t >= n
    let asm = if t < 0 { t + n } else if t >= n { t - n } else { t };
    assert_eq!(r, asm);
}

/// The energy sensor is always a byte, and monotone.
#[cfg_attr(kani, kani::proof)]
pub fn sense_energy_is_byte_and_monotone() {
    let a = i64_in(i64::MIN, i64::MAX - 1);
    let s = sense_energy(a);
    assert!((0..=255).contains(&s));
    assert!(sense_energy(a + 1) >= s);
}

/// food_index is in bounds for every in-world position (finite, 0 <= x < w, 0 <= y < h).
#[cfg_attr(kani, kani::proof)]
pub fn food_index_in_bounds() {
    let fcell = i32_in(1, 16);
    let fw = i32_in(1, 8);
    let fh = i32_in(1, 8);
    let (wd, ht) = ((fw * fcell) as f64, (fh * fcell) as f64);
    let (x, y) = (f64_in(0.0, wd), f64_in(0.0, ht));
    let mut food = [0u8; 64];
    let (mut fert, mut facc) = ([0u8; 64], [0u8; 64]);
    let v = V {
        w: wd, h: ht, used: 0, x: &mut [], y: &mut [], heading: &mut [], age: &mut [], cost: &[],
        last_action: &mut [], energy: &mut [], alive: &mut [], fw, fh, fcell,
        food: &mut food[..(fw * fh) as usize], fert: &mut fert[..(fw * fh) as usize],
        facc: &mut facc[..(fw * fh) as usize], gw: 1, gh: 1, gcell: 24, ghead: &mut [], gnext: &mut [],
    };
    assert!(food_index(&v, x, y) < (fw * fh) as usize);
}

/// A whole sense + act step on a tiny 2-creature world: no panic, no overflow, no
/// out-of-bounds, for any actions, costs, energies, food, fertility, headings and ages.
#[cfg_attr(kani, kani::proof)]
#[cfg_attr(kani, kani::unwind(10))]
pub fn tiny_world_step_is_safe() {
    let mut x = [3.0, 11.5];
    let mut y = [4.0, 9.25];
    let mut heading = [i32_in(0, 63), i32_in(0, 63)];
    let mut age = [i32_in(0, 899), i32_in(0, 899)];
    let mut species = [0, 1];
    let mut cost = [i32_any(), i32_any()];
    let mut last_action = [0, 0];
    let mut energy = [i64_in(-E_BOUND, E_BOUND), i64_in(-E_BOUND, E_BOUND)];
    let mut alive = [bool_any() as u8, bool_any() as u8];
    let mut food = [u8_any(), u8_any(), u8_any(), u8_any()];
    let mut fert = [u8_any(), u8_any(), u8_any(), u8_any()];
    let mut facc = [u8_any(), u8_any(), u8_any(), u8_any()];
    let mut ghead = [-1i32; 1];
    let mut gnext = [-1i32; 2];
    let mut sbuf = [0i32; 12];
    let (mut abuf, mut bbuf, mut dbuf) = ([0i32; 2], [0i32; 2], [0i32; 2]);
    let mut world = World {
        cap: 2, used: 2, w: 16.0, h: 16.0,
        x: x.as_mut_ptr(), y: y.as_mut_ptr(), heading: heading.as_mut_ptr(), age: age.as_mut_ptr(),
        species: species.as_mut_ptr(), cost: cost.as_mut_ptr(), last_action: last_action.as_mut_ptr(),
        energy: energy.as_mut_ptr(), alive: alive.as_mut_ptr(), fw: 2, fh: 2, fcell: 8,
        food: food.as_mut_ptr(), fert: fert.as_mut_ptr(), facc: facc.as_mut_ptr(),
        gw: 1, gh: 1, gcell: 24, ghead: ghead.as_mut_ptr(), gnext: gnext.as_mut_ptr(),
        eaten_total: 0, ticks: 0, deaths_total: 0, backend: 1,
        sbuf: sbuf.as_mut_ptr(), abuf: abuf.as_mut_ptr(), bbuf: bbuf.as_mut_ptr(), dbuf: dbuf.as_mut_ptr(),
    };
    let actions = [i32_any(), i32_any()];
    let (mut births, mut deaths) = ([0i32; 2], [0i32; 2]);
    let (mut nb, mut nd) = (0i32, 0i32);
    let food_before: i64 = food.iter().map(|&f| f as i64).sum();
    unsafe {
        let mut out = [0i32; 12];
        let alive_n = yp_rust_sense(&mut world, out.as_mut_ptr());
        assert!((0..=2).contains(&alive_n));
        for (k, &s) in out.iter().enumerate() {
            match k % 6 { 4 => assert!((0..=15).contains(&s)), _ => assert!((0..=255).contains(&s)) }
        }
        yp_rust_act(&mut world, actions.as_ptr(), 2, 1 << 50, births.as_mut_ptr(), &mut nb, deaths.as_mut_ptr(), &mut nd);
    }
    assert!((0..=2).contains(&nb) && (0..=2).contains(&nd) && nb + nd <= 2);
    assert!(world.eaten_total >= 0 && world.eaten_total <= 18);
    assert_eq!(world.ticks, 1);
    for i in 0..2 {
        assert!(x[i] >= 0.0 && x[i] < 16.0 && y[i] >= 0.0 && y[i] < 16.0);
        assert!((0..64).contains(&heading[i]));
    }
    let _ = food_before;
}

#[cfg(all(test, not(kani)))]
mod randomized {
    const RUNS: u64 = 20_000;
    fn run(f: fn(), salt: u64) {
        for k in 0..RUNS {
            super::gen::seed(k.wrapping_mul(0x9E37_79B9_7F4A_7C15) ^ salt);
            f();
        }
    }
    #[test] fn regrow() { run(super::regrow_bounded_and_exact, 1) }
    #[test] fn eat() { run(super::eat_conserves_food, 2) }
    #[test] fn metabolize() { run(super::metabolize_identity_no_overflow, 3) }
    #[test] fn grid_wrap() { run(super::grid_wrap_in_bounds_matches_asm, 4) }
    #[test] fn sense_energy() { run(super::sense_energy_is_byte_and_monotone, 5) }
    #[test] fn food_index() { run(super::food_index_in_bounds, 6) }
    #[test] fn tiny_world() { run(super::tiny_world_step_is_safe, 7) }
}
