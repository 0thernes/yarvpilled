# Verification ladder: progress log

Append-only log of the v0.4.0 verification work, so an interrupted run can resume.
Times are America/Los_Angeles (PST).

## 2026-11-22

- 16:45 Checkpoint 27f2b51 (claims ledger, mutation tool, replication + verify workflows).
  Already landed before it: Lean 4 spec (31 theorems), Kani harnesses + randomized
  proof-check tests, kernel fuzzer (1 finding fixed), genome fuzzer, ASan+UBSan suite run,
  property, differential and negative tests, pre-registered selection-vs-drift run.
- 16:50 Resumed. Box disk has ~1.2 GB free: the Kani toolchain still cannot be installed here.
  `rake test` at 27f2b51: 58 runs, 2 failures (verification-evidence block drift after the
  mutation run; CHANGELOG has no 0.4.0 entry yet). Both are bookkeeping, not code faults.
- 16:52 Installed CBMC 6.6.0 (apt, 87 MB). Added `formal/cbmc/harness.c` + `check.sh`:
  bounded model checking of the reference C kernel (kernel_c.c included verbatim).
- 17:10 CBMC: food-index wrap, default-world food index, wrapd and tdelta VERIFIED in about 1 s
  each with fully symbolic doubles. Vacuity checked: weakened assertions FAIL as they should.
- 17:15 Fully symbolic positions in the crowd harness did not finish in 600 s (about 10 GB of
  RAM, MiniSat; CaDiCaL is not compiled into Debian's CBMC). Crowd on a 24-unit lattice:
  VERIFIED in 215 s; on a 12-unit lattice: timeout at 420 s. Default set to 24.
- 17:20 Added `formal/cbmc/lattice.sh` (exhaustive execution under ASan+UBSan):
  5,308,416 two-creature ticks, 10,616,832 asm-vs-C crowd comparisons and 5,308,416 Rust-vs-C
  ticks, 0 failures.
- 17:35 Act-tick harness run killed: ACT_CAP=1 exit 137 after 436 s, ACT_CAP=2 exit 15 after 9 s
  (tmp-logs/cbmc-act.log). No act-tick proof is claimed. Correction to 17:15: the logged
  LAT_STEP=12 crowd run ended with exit 124 after 561 s wall clock (tmp-logs/cbmc-crowd2.log).
- 17:45 Final wrap-up run (no new long CBMC/Kani/fuzz/mutation runs). Re-ran the four fast CBMC
  harnesses (VERIFIED, 0-1 s each, 1459 properties) and the vacuity guard (both weakened
  assertions FAIL as required). Recorded `docs/verification/cbmc.json` (5/6 verified,
  h_act_tick_safe KILLED) and the raw log lines in `docs/verification/cbmc_runs.txt`.
  `check.sh` now reports exit 137/143 as KILLED instead of FAILED. `rake test`: 59 runs, 0 failures.
