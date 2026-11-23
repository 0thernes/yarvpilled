# CBMC proofs of the C kernel

`harness.c` `#include`s `ext/yarvpilled_native/kernel_c.c` verbatim, so the code that is
checked is the code that ships. `check.sh` runs each harness with CBMC's memory-safety
(`--bounds-check --pointer-check`), `--signed-overflow-check`, `--conversion-check`
(float/int casts), `--float-overflow-check`, `--nan-check` and `--div-by-zero-check`, with
unwinding assertions so a loop bound that is too small is reported, not silently cut.

| harness | input domain | proves | result on the dev box |
|---|---|---|---|
| `h_food_index_wrap` | every `int` cell coordinate, food grid 1..1,000,000 wide | the `%` wrap never yields an index outside the food grid | VERIFIED (0 s) |
| `h_food_index_default_world` | every finite double point within one world-width of the default 768x512 world | same, with the real double division and float->int conversion | VERIFIED (0 s) |
| `h_wrapd_into_torus` | every finite `m` in [72, 1e6), `v` in [-m, 2m) | `wrapd` lands in [0, m) | VERIFIED (1 s) |
| `h_tdelta_short_way` | every pair of points on a torus of size [72, 1e6) | `|tdelta| <= m/2` | VERIFIED (0 s) |
| `h_crowd_bounded` | 72x72 world, 2 creatures on a position lattice | crowd scan reads in bounds, counts at most used-1 | VERIFIED at LAT_STEP=24 (215 s); LAT_STEP=12 timed out (exit 124 after 561 s); fully symbolic positions timed out (600 s, about 10 GB RAM) |
| `h_act_tick_safe` | 72x72 world, `ACT_CAP` slots (default 1), any used/alive, headings, ages, costs <= 1e6, energies within 2^40, food, actions; positions on a lattice | a whole `yp_c_act` tick is memory-safe and overflow-free; afterwards food <= 255, headings in 0..63, positions on the torus, births + deaths <= used, bounded energy gain | **not completed**: ACT_CAP=1 killed (exit 137) after 436 s; ACT_CAP=2 stopped (exit 15) after 9 s. No proof is claimed |

Recorded results: [docs/verification/cbmc.json](../../docs/verification/cbmc.json), raw log
lines in [docs/verification/cbmc_runs.txt](../../docs/verification/cbmc_runs.txt). CBMC 6.6.0 with
MiniSat on a loaded 8-vCPU / 15 GB box.

**Limits.** The crowd and whole-tick harnesses use a coarse lattice of positions (`LAT_STEP`,
default 24 units: cell corners and seams) because fully symbolic doubles through the
collision math did not fit in the dev box's memory. Even so, `h_act_tick_safe` did not finish
here, so the whole tick is covered by `lattice.sh` (execution) and the fuzzer, not by proof. `lattice.sh` covers a finer lattice
exhaustively by execution: every placement of two creatures on a 3-unit lattice x
every action pair (5,308,416 ticks) under ASan + UBSan, also checking asm crowd == C and
Rust tick == C bit for bit. Neither covers worlds bigger than the minimum or more than two
creatures; the fuzzer and differential tests do.

**Vacuity guard.** `check.sh` re-runs two harnesses with deliberately weakened assertions and
requires them to fail, so over-strong assumptions cannot make a proof pass vacuously.

    formal/cbmc/check.sh [seconds-per-harness]   # RECORD=1 writes docs/verification/cbmc.json
    formal/cbmc/lattice.sh                        # RECORD=1 writes docs/verification/lattice.json
