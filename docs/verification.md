# Verification ladder

Fourteen layers of trying to prove this project wrong. Each layer says what
was actually run, what it found, and what it does **not** cover. Nothing here
gates a commit or a push: the heavy jobs are informational, manual or
scheduled (see `.github/workflows/verify.yml`).

<!-- generated:verification-evidence -->
| evidence | value | source |
|---|---|---|
| claim IDs mapped to commands/tests | 24 | CLAIMS.md |
| property-based cases per test run | 7,350 (x PROP_SCALE) | test/test_*.rb `Prop.check` |
| Lean theorems proved (no sorry) | 31 | formal/lean, `./check.sh` |
| Kani harnesses (randomized stable-Rust runs: 20,000 each) | 7 | ext/yarvpilled_rust/src/proofs.rs |
| kernel fuzzer | 4,321,930 execs in 1,232 s, 0 crashes after fix (1 finding fixed) | docs/verification/kernel_fuzz.json |
| genome fuzzer | 1,940,343 genomes in 600 s, 0 findings | docs/verification/genome_fuzz.json |
| ASan + UBSan test run | 50 tests, 0 failures, 0 sanitizer reports | docs/verification/sanitize.json |
<!-- /generated:verification-evidence -->

| # | layer | status | how to run | evidence |
|---|---|---|---|---|
| 1 | Reproducible builds and numbers | done | `just reproduce` (or `rake reproduce`) | `.ruby-version` 3.4.7, `rust-toolchain.toml` 1.85.1, `formal/lean/lean-toolchain` v4.35.0; no gems, so no Gemfile.lock. `tools/reproduce.rb` re-derives every deterministic headline number from a clean build: 15/15 bit-for-bit on the box (Ruby 3.4.7) |
| 2 | Claims map | done | `ruby tools/claims.rb` | [CLAIMS.md](../CLAIMS.md): claim IDs → command → test. README numbers live in generated blocks; `test_claims.rb` fails on drift, and recomputes some numbers independently of the generator |
| 3 | Falsifiable + negative tests | done | `rake test` | each claim ID names a test that fails if the claim breaks; `test_negative.rb` rejects bad worlds, spawns, fertility maps, genomes (22 hostile shapes) and CLI args (exit 2) |
| 4 | Property-based tests | done | `rake test` (`PROP_SCALE=10` for a soak) | stdlib-only generator (`test/support/prop.rb`), edge-biased, every failure prints a one-line repro. Energy accounting, bounds on every backend, determinism, mutation chains, junk genomes |
| 5 | Differential testing | done | `ruby -Itest test/test_differential.rb` | C vs asm vs Rust vs Ruby vs a deliberately simple O(n²) reference stepper (`test/support/reference_world.rb`, no grid, written from the rules) on 300 random worlds per run, compared after every tick |
| 6 | Mutation testing | done | `ruby tools/mutate.rb` | homegrown runner: operator/comparison/literal/boolean mutants of the world, genome grammar, statistics and digest code, one at a time, against their tests. Score and every survivor in `docs/verification/mutation.json` |
| 7 | Fuzzing + sanitizers | done | `fuzz/run.sh 1200`, `ruby tools/genome_fuzz.rb --seconds=600`, `RECORD=1 rake sanitize` | libFuzzer differential kernel fuzzer under ASan+UBSan (found and fixed one spec gap, then 0 crashes); genome fuzzer; the whole Ruby suite against an ASan+UBSan build of the C extension |
| 8 | Static checks | done | `just lint` | `-Wall -Wextra` clean (gcc 14), `cargo clippy --all-targets --features proof-check -D warnings` clean, `ruby -w` clean over the whole test suite. CI job `static` is informational |
| 9 | Formal methods | partial | `formal/lean/check.sh`; `cargo kani` (CI) | Lean 4: theorems about the integer step, no sorry, executable mirror differential-tested against every backend. Kani: 7 harnesses; **not run on the dev box** (no disk for the Kani toolchain), run by the manual/scheduled `kani` CI job; the same harness bodies run as 20,000-case randomized tests on stable Rust |
| 10 | Honest benchmarks | done | `rake bench` | hardware and toolchain captured in `docs/bench.json`; a correctness checksum/digest next to every timing; median (min-max) of 5 fresh processes; losses kept (asm doesn't beat gcc by much; the previous run is kept as `docs/bench_v0.2.0.md`); verdict is generated and says "tied" only when the gap is below the noise |
| 11 | Statistics | done | `rake control` | pre-registered ([preregistration.md](preregistration.md), committed before the data), n = 20 per arm, Monte Carlo permutation test (100k), Holm, bootstrap CIs (10k) for the difference and Cohen's d; `test_stats.rb` checks the statistics against hand values and a brute-force oracle |
| 12 | Provenance | done (on next release) | push a `v*` tag | `release.yml` builds the gem and source archive, writes `SHA256SUMS`, and attests build provenance with `actions/attest-build-provenance`. How to verify: [provenance.md](provenance.md) |
| 13 | Limitations | done | read it | [LIMITATIONS.md](../LIMITATIONS.md), including "what would prove us wrong" |
| 14 | Independent replication | started | `just replicate` | [REPLICATION.md](../REPLICATION.md): one-command protocol, issue form, and the `replicate` CI workflow (Linux/macOS/Windows runners). First entries are this box; CI-runner entries are pending until the workflow runs on GitHub |

## Findings so far

The ladder found three real problems, all fixed:

1. **Integer overflow in metabolism** (Kani/proof-check harness): `3 + cost` overflowed
   `int32` for extreme costs (undefined behaviour in C, a panic in debug Rust). Now computed in
   64 bits. Real costs are small, so every recorded number is unchanged.
2. **Tiny worlds break the torus** (kernel fuzzer, after 7,176 executions): with fewer than 3
   grid cells per axis, a collision push could leave the world after one wrap step and the 3x3
   neighbourhood aliased, double-counting crowding. All backends agreed, so it was a gap in the
   spec rather than a backend bug. `World.new` now rejects such worlds (and NaN, infinite or
   huge sizes, bad food cells and capacities) on every backend. Real runs use 768x512.
3. **Unvalidated spawn positions**: `spawn(NaN, ...)` or far-away coordinates produced a
   creature outside the torus. Now an ArgumentError, before a slot is taken.

And one documented quirk that is *not* fixed, on purpose: when the world size is not a
multiple of the 24-unit grid cell (the default height 512 is not), creatures on either side of
the seam can miss each other in the crowd and collision scans. Every backend and the reference
stepper agree on this, and changing it would change every recorded result, so it is part of
the spec and listed in [LIMITATIONS.md](../LIMITATIONS.md).

## What is not verified

- Kani was not run locally (see layer 9). The harnesses compile under `cfg(kani)` only in CI.
- The CI-runner replications on macOS and Windows have not run yet (they need a push).
- Mutation testing samples at most 120 mutants per target, and only the files listed in
  `tools/mutate.rb`. The C, asm and Rust kernels are covered by differential tests and the
  fuzzer, not by mutation testing.
- Coverage-guided fuzzing instruments only the C kernel and the harness; asm and Rust are
  checked differentially.
- The Lean model covers integer bookkeeping only (see `formal/lean/README.md`).
