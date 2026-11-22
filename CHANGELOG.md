# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/0thernes/yarvpilled/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/0thernes/yarvpilled/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/0thernes/yarvpilled/releases/tag/v0.2.0
[0.1.0]: https://github.com/0thernes/yarvpilled/commit/39effb6f014d78b6e0006b374264b98f3bcb5b61
