# Verification ladder

Fourteen layers of trying to prove this project wrong. Each layer says what
was actually run, what it found, and what it does **not** cover. Nothing here
gates a commit or a push: the heavy jobs are informational, manual or
scheduled (see `.github/workflows/verify.yml`).

<!-- generated:verification-evidence -->
| evidence | value | source |
|---|---|---|
| claim IDs mapped to commands/tests | 25 | CLAIMS.md |
| property-based cases per test run | 7,650 (x PROP_SCALE), plus 1,500 Lean-mirror cases when Lean is installed | test/test_*.rb `Prop.check` |
| Lean theorems proved (no sorry) | 31 | formal/lean, `./check.sh` |
| Kani harnesses (Kani itself runs in CI only; locally each body ran as 20,000 randomized stable-Rust cases) | 7 | ext/yarvpilled_rust/src/proofs.rs |
| kernel fuzzer | 4,321,930 execs in 1,232 s, 0 crashes after fix (1 finding fixed) | docs/verification/kernel_fuzz.json |
| genome fuzzer | 1,940,343 genomes in 600 s, 0 findings | docs/verification/genome_fuzz.json |
| mutation score | 88.5% (392/443 mutants killed) | docs/verification/mutation.json |
| CBMC harnesses on the C kernel | 5/6 verified (h_act_tick_safe: KILLED) | docs/verification/cbmc.json |
| exhaustive lattice check (ASan + UBSan) | 5,308,416 ticks, 10,616,832 asm-vs-C crowd scans, 5,308,416 Rust-vs-C ticks, 0 failures | docs/verification/lattice.json |
| ASan + UBSan test run | 50 tests, 0 failures, 0 sanitizer reports | docs/verification/sanitize.json |
<!-- /generated:verification-evidence -->

Status key: **verified** = run on the dev box (Linux x86-64, Ruby 3.4.7) with the recorded
result shown (layer 12 runs on GitHub instead); **partial** = some of the layer ran, the rest is named with the reason;
**not run here** = wired up, but it has not produced a result yet.

| # | layer | status | why this status | how to run | evidence |
|---|---|---|---|---|---|
| 1 | Reproducible builds and numbers | verified | `tools/reproduce.rb` re-derived every deterministic headline number from a clean build on the box: 15/15 bit for bit (c, asm, rust, ruby worlds), and 9/9 with `YARVPILLED_PURE=1` | `just reproduce` (or `rake reproduce`) | [docs/replications/box-ruby34.json](replications/box-ruby34.json), [box-ruby34-pure.json](replications/box-ruby34-pure.json); pins: `.ruby-version` 3.4.7, `rust-toolchain.toml` 1.85.1, `formal/lean/lean-toolchain` v4.35.0; no gems, so no Gemfile.lock |
| 2 | Claims map | verified | `test_claims.rb` passes: every claim ID resolves, generated blocks match the data, key numbers recomputed independently | `ruby tools/claims.rb` | [CLAIMS.md](../CLAIMS.md), `test/test_claims.rb` |
| 3 | Falsifiable + negative tests | verified | part of the green `rake test` (59 runs, 0 failures) | `rake test` | `test/test_negative.rb`: bad worlds, spawns, fertility maps, 22 hostile genome shapes, CLI args (exit 2) |
| 4 | Property-based tests | verified | part of the green `rake test`; 7,650 generated cases per run at the default scale, plus 1,500 Lean-mirror cases when Lean is installed | `rake test` (`PROP_SCALE=10` for a soak) | `test/support/prop.rb` (stdlib-only, edge-biased, one-line repro per failure); energy accounting, bounds on every backend, determinism, mutation chains, junk genomes |
| 5 | Differential testing | verified | 300 random worlds per test run vs a simple O(n²) reference stepper, plus the exhaustive lattice run (0 failures) | `ruby -Itest test/test_differential.rb`; `formal/cbmc/lattice.sh` | `test/support/reference_world.rb`; [lattice.json](verification/lattice.json): every placement of two creatures on a 3-unit lattice x every action pair (5,308,416 ticks), asm crowd vs C and Rust tick vs C, bit for bit |
| 6 | Mutation testing | partial | ran on the Ruby side only (world port, genome grammar, statistics, digest): 392/443 killed (88.5%; 4 of the kills are timeouts), 51 survivors listed; the C, asm and Rust kernels are not mutated (covered by differential tests and the fuzzer) | `ruby tools/mutate.rb` | [mutation.json](verification/mutation.json) (per target: world_ruby 227/270, genome 84/86, control 79/85, digest 2/2) |
| 7 | Fuzzing + sanitizers | verified | kernel fuzzer 4,321,930 execs in 1,232 s with 0 crashes after its one fix; genome fuzzer 1,940,343 genomes in 600 s, 0 findings; ASan+UBSan suite 50 tests, 0 reports. Coverage instrumentation is on the C kernel only | `fuzz/run.sh 1200`, `ruby tools/genome_fuzz.rb --seconds=600`, `RECORD=1 rake sanitize` | [kernel_fuzz.json](verification/kernel_fuzz.json), [genome_fuzz.json](verification/genome_fuzz.json), [sanitize.json](verification/sanitize.json) |
| 8 | Static checks | verified | `-Wall -Wextra` clean (gcc 14), `cargo clippy --all-targets --features proof-check -D warnings` clean, `ruby -w` clean over the suite | `just lint` | [lint.txt](verification/lint.txt); CI job `static` is informational |
| 9 | Formal methods | partial | **Lean 4: verified**, 31 theorems, no `sorry`. **CBMC 6.6: 5 of 6 harnesses verified**; `h_act_tick_safe` (a whole tick) never finished on the box: ACT_CAP=1 killed (exit 137) after 436 s, ACT_CAP=2 stopped (exit 15) after 9 s. The crowd harness is verified only on a 24-unit position lattice (215 s); a 12-unit lattice timed out (exit 124 after 561 s) and fully symbolic positions timed out at 600 s. **Kani: not run here**: its toolchain does not fit on the box's disk (about 1 GB free); the 7 harnesses run only in the manual/scheduled `kani` CI job, and locally the same bodies ran as 20,000-case randomized tests on stable Rust | `formal/lean/check.sh`; `formal/cbmc/check.sh`; `cargo kani` (CI) | [lean_check.txt](verification/lean_check.txt), [cbmc.json](verification/cbmc.json), [cbmc_runs.txt](verification/cbmc_runs.txt), [formal/cbmc/README.md](../formal/cbmc/README.md), `ext/yarvpilled_rust/src/proofs.rs` |
| 10 | Honest benchmarks | verified | recorded on the box with hardware and toolchain captured, a correctness checksum/digest next to every timing, median (min-max) of 5 fresh processes, losses kept | `rake bench` | [bench.json](bench.json), [bench.md](bench.md), previous run kept as [bench_v0.2.0.md](bench_v0.2.0.md) |
| 11 | Statistics | verified | pre-registered ([preregistration.md](preregistration.md), committed before the results commit; git shows commit order only), n = 20 per arm, permutation tests (100k) with Holm, bootstrap CIs (10k), Cohen's d; H1-H5 supported; `test_stats.rb` checks the statistics against hand values and a brute-force oracle | `rake control` | [control.json](control.json), [control.md](control.md) |
| 12 | Provenance | partial | the v0.4.0 release workflow ran on GitHub (Nov 23, 2026). Re-checked from the box on Nov 24, 2026 (PT): `sha256sum -c SHA256SUMS` passes for all 4 assets, `git archive` of the tag reproduces the source tarball bit for bit (git 2.47.3), and GitHub's attestation API lists one provenance attestation per asset digest. The Sigstore signatures themselves were not verified here (`gh attestation verify` needs a signed-in `gh`) | [provenance.md](provenance.md) steps 1-3 | `.github/workflows/release.yml`, [provenance.md](provenance.md), the [v0.4.0 release](https://github.com/0thernes/yarvpilled/releases/tag/v0.4.0) |
| 13 | Limitations | verified | written and kept in step with this table, including "what would prove us wrong" | read it | [LIMITATIONS.md](../LIMITATIONS.md) |
| 14 | Independent replication | partial | the dev box replicated (same hardware as the original runs, so this shows reproducibility, not portability), and so did the author's Windows 11 PC in pure Ruby (Ruby 3.4.9, another CPU and libm: 9/9 bit for bit). Both machines belong to the author; the Linux/macOS/Windows CI-runner replications have not run yet (manual or monthly `Replicate` workflow), and no outside replication exists | `just replicate` | [REPLICATION.md](../REPLICATION.md), [docs/replications/](replications/) |

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

- **Kani was not run here** (layer 9): its toolchain needs more disk than the box has. The
  harnesses compile under `cfg(kani)` only in CI; locally only their randomized stable-Rust
  twins ran.
- **CBMC did not prove a whole tick.** `h_act_tick_safe` was killed before it finished (exit
  137 after 436 s at ACT_CAP=1; exit 15 after 9 s at ACT_CAP=2). The whole tick is covered by
  exhaustive execution on the 3-unit lattice (`lattice.sh`), the fuzzer and differential
  tests, not by proof.
- CBMC proves the crowd scan only on the minimal 72x72 world, with 2 creatures on a 24-unit
  position lattice (cell seams). The 12-unit lattice (exit 124 after 561 s) and fully symbolic
  positions (600 s, about 10 GB RAM) timed out. Rust and asm are not model-checked directly
  (Kani covers Rust helpers in CI; asm is checked differentially).
- The CBMC evidence was assembled from logged runs plus a re-run of the four fast harnesses
  and the vacuity guard, not from one uninterrupted `RECORD=1 formal/cbmc/check.sh` run.
- The CI-runner replications on Linux, macOS and Windows have not run yet. The `Replicate`
  workflow runs only by hand (workflow_dispatch) or on its monthly schedule (the 3rd, 05:41 UTC).
- The provenance attestations exist for every v0.4.0 asset, but their Sigstore signatures were
  not verified from here; run `gh attestation verify` (docs/provenance.md step 2) to check them.
- Mutation testing samples at most 120 mutants per target, and only the files listed in
  `tools/mutate.rb`. The C, asm and Rust kernels are covered by differential tests and the
  fuzzer, not by mutation testing. 51 mutants survived; they are listed in `mutation.json` but
  not triaged (some may be equivalent, some may be test gaps).
- Coverage-guided fuzzing instruments only the C kernel and the harness; asm and Rust are
  checked differentially.
- The Lean model covers integer bookkeeping only (see `formal/lean/README.md`).
