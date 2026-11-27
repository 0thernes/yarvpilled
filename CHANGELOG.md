# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Build Standard v1.2.0 agent entry points and manifest: `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`,
  `.cursor/rules/build-standard.mdc`, `llms.txt`, `docs/configuration.md`, and `repo.yaml`.
- `formal/lean/VerifyAxioms.lean`: explicit `#print axioms` audit covering all 31 theorems in
  `Yarvpilled.Slots` (8) and `Yarvpilled.Spec` (23), confirming strictly standard axioms
  `[propext, Classical.choice, Quot.sound]`, zero `sorry`/`admit`/`native_decide`, and zero custom axioms.
- Lean 4.35.0 `module` headers (`@[expose] public section`) on `Yarvpilled.lean`, `Yarvpilled/Slots.lean`,
  `Yarvpilled/Spec.lean`, and `VerifyAxioms.lean` (`Mirror.lean` stays a non-module executable script so
  `lake env lean --run Mirror.lean` works cleanly); `formal/lean/check.sh` updated to run
  `VerifyAxioms.lean`, enforce the strict standard-axiom allowlist, and replay via
  `lake env leanchecker --fresh Yarvpilled`.
- Explicit falsification summary section in `CLAIMS.md` and ORCID / independent-researcher metadata in
  `CITATION.cff`.

## [0.4.1] - 2026-11-24

A hardening pass over every file: code, docs, CI and the claims ledger. No simulation rule or
recorded result changed (the C glue and rasterizer now only widen or reject out-of-range
values), and every recorded number still reproduces bit for bit.

### Fixed
- **CI was red on v0.4.0.** `actions/checkout` fetches one commit, so the git check that the
  pre-registration predates the results failed on Linux and macOS. CI now fetches full history,
  and the test skips with a message on a shallow clone instead of failing.
- **The test suite hung on Windows.** With Ruby 3.4 on Windows, minitest's idle parallel-executor
  threads deadlocked the Ractor expert vote at tick 120 (standalone runs were fine).
  `test_helper.rb` sets `MT_CPU=0` on Windows; the suite passes there (59 runs, 0 failures).
- **Checkout paths containing `[ ]` broke two tools.** `tools/claims.rb` (test and theorem counts)
  and the Rakefile (native library lookup) passed absolute paths to `Dir[]`, which reads brackets
  as a glob class. Both now glob with `base:`.
- README badges: claims 24 -> 25; the YJIT docs link (404) now points at the 3.4 docs.
- README: `rake control` defaults are the pre-registered run (20 seeds from 201, 4000 ticks);
  energy drain per tick is `3 + cost` (+3 dashing), not just the genome cost.
- FAQ: the selection answer quoted the 8-seed pilot; it now gives the pre-registered numbers.
  The Rust-vs-C/asm gap is 11% / 17% on the recorded kernel-only medians.
- `SECURITY.md` listed 0.3.x as the supported line; it is 0.4.x.
- The property-case count in the verification ladder missed tests that use a named constant;
  it is 7,650 (x `PROP_SCALE`), plus 1,500 Lean-mirror cases when Lean is installed.
- **Native energy was narrowed to 32 bits on Windows.** The C glue converted the `int64_t`
  energy and tick/eaten/death counters with `NUM2LONG`/`LONG2NUM`; C `long` is 32 bits on
  Windows, so values past 2^31 were truncated (snapshot, split, stats) or rejected (spawn,
  feed). It now uses `NUM2LL`/`LL2NUM`. Recorded runs never reach 2^31, so no number changes.
- **The C rasterizer trusted its size arguments.** Negative or overflowing buffer sizes passed
  the length check (products were computed in `long`, 32 bits on Windows), and `heat` with zero
  columns or rows divided by zero. Sizes are now checked in 64-bit and must be positive; bad
  sizes raise `ArgumentError`. The renderer's own calls are unchanged.
- The replication issue form was invalid YAML (an unquoted `label: Optional: ...`), so GitHub
  could not show it. A test now parses every workflow, issue form, `CITATION.cff` and data file.
- **The v0.4.0 GitHub Release notes were cut off after one paragraph.** The Release workflow's
  extractor stopped at any line starting with `[`, and the 0.4.0 notes have a body line that
  starts with a Markdown link. Extraction moved to `tools/release_notes.rb`, which stops only at
  the next version heading or the link definitions; a test checks every section comes out whole.
  (The published v0.4.0 release body itself is unchanged.)
- ADR 0006 notes that its n = 8 and exact-test figures are the pilot's; the README quotes the
  pre-registered n = 20 Monte Carlo permutation run.
- CONTRIBUTING's release steps now list every file that carries the version.
- README: the limitations summary said Windows was CI-only; it has a recorded pure-Ruby
  replication on the author's PC.
- README: the asm scan runs on x86-64 Linux/BSD; macOS (Intel too) uses the C scan.
- `formal/cbmc/check.sh` exits if its `cd` fails.
- `.gitattributes` comment said CRLF on Windows; the rules force LF everywhere.

### Changed
- Pre-registration is described as what git can show: the plan commit (`316a27f`) precedes the
  results commit (`a6aed90`). Git shows commit order, not when the run happened.
- Layer 12 (provenance) is now **partial**, not "not run": the v0.4.0 release workflow ran,
  `sha256sum -c` passes on its assets, `git archive` reproduces the source tarball and GitHub
  lists an attestation per asset; the attestation signatures were not verified here.
- Layer 14 adds a third machine: the author's Windows 11 PC, pure Ruby, 9/9 recorded numbers bit
  for bit (`docs/replications/alex-pc-win11-ruby349-pure.json`). Still no outside replication.
- The Replicate workflow is described as it is: manual or monthly, never on push.

### Added
- Tests that the README badges and the verified/partial status line match their data, and that
  the README BibTeX and the Lean package carry the current version.

## [0.4.0] - 2026-11-22

A 14-layer verification ladder: every attempt we could make to prove this project wrong, with
the recorded result of each. On the dev box 10 layers are verified, 3 are partial (mutation
testing, formal methods, replication) and 1 has not run yet (release provenance, which runs
when this tag reaches GitHub). Status and reasons per layer:
[docs/verification.md](docs/verification.md).

### Added
- **Claims ledger** ([CLAIMS.md](CLAIMS.md)): every README claim has an ID, the command that
  produces it and the test that fails if it breaks. README numbers live in generated blocks
  (`tools/claims.rb`); `test_claims.rb` fails on drift and recomputes key numbers independently.
- **Pre-registered statistics**: the confirmatory selection-vs-drift run (n = 20 per arm, seeds
  201-220) was committed as a plan before it ran; H1-H5 supported (Holm-corrected permutation
  tests, bootstrap CIs, Cohen's d). `test_claims.rb` checks in git that the plan predates the data.
- **Lean 4 spec** (`formal/lean`, 31 theorems, no `sorry`) of the integer step, plus an
  executable mirror differential-tested against every backend (1,500 scenarios).
- **Kani harnesses** (7) for the Rust kernel; the same bodies run as 20,000-case randomized
  tests on stable Rust (`cargo test --features proof-check`). Kani itself runs in CI only (its
  toolchain did not fit on the dev box), so there is no recorded Kani result yet.
- **CBMC harnesses** (`formal/cbmc`) on the reference C kernel, included verbatim, with memory,
  signed-overflow, float-conversion, overflow and NaN checks, plus a vacuity guard. 5 of 6
  verified on the dev box: food-index wrap, default-world food index, torus wrap and short-way
  delta over all finite doubles, and the crowd scan on a 24-unit position lattice (215 s). The
  whole-tick harness `h_act_tick_safe` did not finish (killed, exit 137, after 436 s), and the
  crowd scan timed out on a 12-unit lattice (561 s) and with fully symbolic positions (600 s).
  Recorded in `docs/verification/cbmc.json`; `check.sh` reports killed runs as KILLED.
- **Exhaustive lattice check** (`formal/cbmc/lattice.sh`): 5,308,416 two-creature ticks on the
  smallest legal world under ASan + UBSan, asm crowd scan vs C and Rust tick vs C, bit for bit.
- **Property-based tests** (stdlib-only generator), a **differential** suite against a
  deliberately simple O(n^2) reference stepper, **negative tests** (hostile worlds, genomes,
  CLI args) and edge-case tests.
- **Fuzzing**: a libFuzzer differential kernel fuzzer (C vs asm vs Rust) under ASan + UBSan,
  a time-bounded genome fuzzer, and a minimized committed corpus.
- **Sanitizers**: `rake sanitize` runs the whole Ruby suite against an ASan + UBSan build of
  the C extension.
- **Mutation testing**: `tools/mutate.rb`, a homegrown runner over the world, genome grammar,
  statistics and digest code: 392/443 mutants killed (88.5%); every survivor is listed in
  `docs/verification/mutation.json`. The native kernels are not mutation-tested.
- **Reproducibility**: pinned toolchains (`.ruby-version`, `rust-toolchain.toml`,
  `lean-toolchain`), `tools/reproduce.rb` (`just reproduce`) re-derives every deterministic
  headline number from a clean build.
- **Replication**: [REPLICATION.md](REPLICATION.md), an issue form, `just replicate`, and a
  `replicate` workflow on Linux, macOS and Windows runners. First reports, from the dev box
  only: 15/15 checks bit for bit with every backend, 9/9 pure Ruby (`docs/replications/`).
- **Provenance**: the release workflow writes `SHA256SUMS` and attests build provenance;
  how to verify: [docs/provenance.md](docs/provenance.md).
- [LIMITATIONS.md](LIMITATIONS.md), including "what would prove us wrong".
- `verify.yml`: the heavy jobs (Kani, fuzzing, sanitizers, mutation, CBMC), manual or
  scheduled and informational only. `docs/verification/PROGRESS.md` logs the work.

### Changed
- Benchmarks capture hardware and toolchain and record a correctness digest next to every
  timing; trig comes from a committed bit-exact table instead of libm.
- Strict genome grammar: genomes outside it raise `InvalidGenome` before rendering or compiling.

### Fixed
- Integer overflow in metabolism for extreme costs (found by the Kani/proof-check harness);
  now computed in 64 bits. Recorded numbers are unchanged.
- Worlds with fewer than 3 grid cells per axis broke the torus (found by the kernel fuzzer);
  `World.new` now rejects them, and NaN, infinite or huge sizes, bad food cells and capacities.
- `spawn` with NaN or far-away coordinates created a creature off the torus; now an ArgumentError.

## [0.3.0] - 2026-11-22

### Added
- GitHub Pages demo: `tools/build_site.rb` (`rake site`, `just site`) records a 900-tick run of the
  real simulation as gzipped NDJSON telemetry, and `public/index.html` plays it back in replay mode.
  `.github/workflows/pages.yml` builds it in CI. The recording is never committed.
- Windows CI job (RubyInstaller + DevKit). It is informational and marked `continue-on-error`.
- `yarvpilled.gemspec` and the `exe/yarvpilled` CLI (`rake gem`). The C extension compiles on install;
  the Rust backend stays repo-only.
- `justfile` with cross-platform recipes (PowerShell on Windows).
- `tools/labels.rb` (`rake labels`): the issue label set, synced with `gh label create --force`.
- `ROADMAP.md` and `docs/social-preview.png` (1280x640).

### Changed
- CONTRIBUTING trimmed to the essentials. CI is explicitly informational, with per-job timeouts.
- The browser page labels the world backend correctly (C / asm / Rust / pure Ruby) and shows
  LIVE vs REPLAY.
- `yarv_brain.rb` writes to `./out` in the current directory by default, so it works from an
  installed gem.

## [0.2.0] - 2026-11-22

### Added
- `:rust` world backend: the whole sense/act kernel in Rust (staticlib, C ABI, no crates, LTO),
  linked into the ruby.h extension and bit-identical to the C kernel.
- `:asm` world backend: the C kernel with its hottest piece, the crowd-sensing spatial-hash scan,
  in hand-written x86-64 assembly (`crowd_x86_64.S`, SysV, scalar SSE2, cmov grid wrap).
- `World#backend` and `World#kernel_bench` (kernel-only timing with no Ruby in the loop).
- Benchmark with 6 tiers, N fresh-process repeats, median and min-max spread; full-sim
  creatures/sec and generations/sec; per-phase time shares (brains / ISeq compile / world);
  world-loop throughput via the Ruby API and kernel-only; crowd-scan ns/creature.
- Selection vs random-drift control experiment (`--control`, `rake control`): same seeds, brains
  still executed, random actions + flat cost in the null arm, common-garden foraging assay, exact
  permutation test with Holm-Bonferroni correction, species/opcode entropy, bytecode length.
- `Simulation#control` (`:selection` / `:drift`) and `Simulation#prof` (per-phase timers).
- `YARVPILLED_PURE=1` forces the pure-Ruby path; `yarv_brain.rb --version` lists available backends.
- Rake tasks: `smoke`, `bench`, `control`, `video`, `clean`; `VERSION` file.
- Repository hygiene: CONTRIBUTING, CODE_OF_CONDUCT, SECURITY, SUPPORT, CITATION.cff, issue forms,
  `.editorconfig`, `.gitattributes`, architecture/ADR/FAQ docs, release workflow, macOS CI job.

### Changed
- C extension split into `kernel_c.c` (pure C kernel on plain buffers) and `world.c` (Ruby glue);
  every backend shares the same Array <-> buffer conversion, so benchmarks compare kernels only.
- `rake compile` falls back to pure Ruby (with a warning) when the native build fails, unless
  `YP_STRICT=1`; on Windows it enables the RubyInstaller DevKit and skips Rust.
- C flags: `-std=gnu99 -ffp-contract=off` so clang (e.g. macOS arm64) can't fuse multiply-adds and
  break bit-identity with the Ruby and Rust ports.
- README GIF re-encoded (640 px, 10 fps, 10 s, 6.4 MB, down from 11 MB).

### Fixed
- The 0.1.0 "world-loop micro" numbers overstated the native tiers: the loop ran past `MAX_AGE`
  (900 ticks), so most bodies had died while updates were still counted per spawned body. The
  micro now runs 600-tick blocks on fresh worlds and counts live bodies only.

## [0.1.0] - 2026-11-21

### Added
- A-Life core: a 768x512 toroidal world of creatures that move, eat, reproduce and die. Each
  creature's brain is a real Ruby lambda compiled with `RubyVM::InstructionSequence`,
  round-tripped through `to_binary`/`load_from_binary`, and installed with `define_method`.
- Body phenotype (hue, size, polygon sides, glow) derived only from the genome's opcode histogram
  and bytecode length; metabolic cost scales with bytecode length.
- Natural selection events: TracePoint(:call) gene transfer that rewrites a live method mid-call,
  Ractor hive-mind votes, `GC.compact` "enlightenment", `GC.start` "amnesia", `prepend` survival
  instinct, Refinement guardrail, ObjectSpace-sourced mutation constants.
- `ext/yarvpilled_native`: ruby.h-only C extension for the world loop (spatial hash, resource
  field, movement, collision, death) and a software rasterizer.
- Pure-Ruby world port, bit-identical to the C version (tested).
- Outputs: H.264 MP4 + GIF + PNG stills rendered in-process; ANSI truecolor TUI; stdlib
  TCPServer + SSE browser mode with a canvas renderer.
- 3-tier benchmark (interpreter / YJIT / C ext + YJIT) with an identical-work checksum.

### Fixed
- Worked around a YJIT 3.4.7 panic on fixed-arity cfuncs with more than 5 arguments by exposing
  those C entry points as variadic.

[Unreleased]: https://github.com/0thernes/yarvpilled/compare/v0.4.1...HEAD
[0.4.1]: https://github.com/0thernes/yarvpilled/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/0thernes/yarvpilled/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/0thernes/yarvpilled/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/0thernes/yarvpilled/releases/tag/v0.2.0
[0.1.0]: https://github.com/0thernes/yarvpilled/commit/39effb6f014d78b6e0006b374264b98f3bcb5b61
