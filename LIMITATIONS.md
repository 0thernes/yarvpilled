# Limitations

What this project does not show, where its numbers are weak, and what would
prove it wrong. If you find one of these, please open an issue: a refutation
is as welcome as a replication ([REPLICATION.md](REPLICATION.md)).

## Scope

- **It is a genetic-programming A-Life sim.** "Consciousness", "enlightenment" and
  "hive-mind" are labels for the visuals (see the real-vs-metaphor table in the README).
- **The speed numbers are about one small kernel on one machine.** A pointer-chasing
  spatial-hash scan, on an 8-vCPU virtualized Intel Xeon that was busy at the time (load
  average about 4.9 at the start of the recorded run). Run-to-run spread reached 10-30%. Treat
  the native tiers as tied; do not read a ranking into them.
- **The evolution result is one experimental design.** One assay arena, 4000 ticks (about
  10-15 generations), n = 20 seeds per arm, one mutation operator set, one drift null model.
  A different arena or a longer run could change the effect sizes.
- **Runs with events on are not bit-reproducible.** Ractor votes and GC events depend on
  scheduling. The benchmark and the control experiment turn events off; those runs are
  deterministic.

## Known gaps in the verification

- **Floating point is checked by testing, not proof.** The Lean 4 spec covers the integer
  bookkeeping (food, energy, sensors clamps, slots). Positions, trig, crowding and collisions
  use IEEE-754 doubles and are covered only by differential tests and fuzzing.
- **Kani was not run on the development box** (not enough disk for its toolchain: about 1 GB
  free). The 7 harnesses run only in the manual/scheduled `kani` CI job and have no recorded
  result yet; locally, the same bodies ran as 20,000-case randomized tests on stable Rust,
  which samples inputs and proves nothing.
- **CBMC proved 5 of 6 harnesses, not a whole tick.** `h_act_tick_safe` never finished on the
  box (ACT_CAP=1 killed with exit 137 after 436 s; ACT_CAP=2 stopped with exit 15 after 9 s).
  The crowd-scan proof holds only on a 72x72 world with 2 creatures on a 24-unit position
  lattice (215 s); a 12-unit lattice timed out (exit 124 after 561 s) and fully symbolic
  positions timed out at 600 s. Finer placements are covered by exhaustive execution
  (`formal/cbmc/lattice.sh`, 5,308,416 ticks), which is testing, not proof. Recorded in
  [docs/verification/cbmc.json](docs/verification/cbmc.json).
- **Cross-platform bit-identity is tested on Linux x86-64 only so far.** macOS/arm64 and
  Windows have CI jobs and a replication workflow, but no recorded replication yet. The only
  replications are from the dev box, the same hardware as the original runs.
- **Provenance is wired up but unexercised.** The release workflow's checksums and build
  attestation run only when a `v*` tag reaches GitHub.
- **One libm dependence remains.** Direction vectors come from literal IEEE-754 tables, but
  `Simulation#fertility_bytes` still calls `Math.cos`, `Math.sin` and `Math.exp` once at
  startup. A libm that rounds differently (another OS, another libc) could produce a different
  fertility map and therefore different checksums. The world kernels themselves would still
  agree with each other.
- **Grid-seam quirk.** When the world size is not a multiple of the 24-unit grid cell (the
  default height 512 is not), creatures on opposite sides of the seam can miss each other in
  the crowd and collision scans. All backends and the reference stepper agree, so it is part
  of the spec; fixing it would change every recorded result.
- **Mutation testing covers the Ruby side** (world, genome grammar, statistics, digest),
  sampled at up to 120 mutants per target: 392/443 killed (88.5%), 51 survivors listed but
  not triaged. The C, asm and Rust kernels are covered by the
  differential tests and the fuzzer instead.
- **ISeq binaries are Ruby-version-specific.** They are never persisted across runs.
- **The asm backend is x86-64 SysV only** (Linux/BSD); elsewhere `:asm` uses the C scan. The
  Rust backend is not wired up on Windows.

## What would prove us wrong

Each of these is a concrete observation that would falsify a claim in
[CLAIMS.md](CLAIMS.md):

| if you observe... | it falsifies |
|---|---|
| two backends producing different sensors, births, deaths or state digests for the same world | C-EQ-1 |
| `tools/reproduce.rb` printing FAIL on a clean checkout (on Linux x86-64 with Ruby 3.4) | C-BENCH-1, C-BENCH-2, C-CTRL-1 |
| a different checksum on another OS that persists after pinning the fertility map | cross-platform determinism (a libm effect is the first suspect) |
| a native tier consistently more than ~10% faster than the others across repeated `rake bench` runs on a quiet machine | C-BENCH-3 ("tied within noise") |
| the brain share falling well below ~70% on native tiers | C-BENCH-4 |
| `rake control` with new seeds (e.g. `FIRST_SEED=301`) giving Holm p ≥ 0.05 or the opposite sign for fitness or survival | C-CTRL-2 (the result would be seed-dependent) |
| a drift arm matching selection when the assay arena or tick count changes modestly | the generality of C-CTRL-2 |
| any genome that passes `Genome.validate!` but fails to compile, returns a non-Integer, or renders an identifier outside the whitelist | C-INV-3, C-NEG-2 |
| a creature's energy change that is not `take + take/2 − metabolism` | C-INV-1 |
| a sanitizer report, a fuzzer crash, or a surviving mutant that is not equivalent | the corresponding layer in docs/verification.md |
