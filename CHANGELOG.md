# Changelog

## 0.2.0 (2026-11-21)

- New world-loop backends, all bit-identical to the C kernel and sharing one Ruby glue layer:
  - `:rust`: whole sense/act kernel in Rust (staticlib, C ABI, no crates), linked into the ruby.h extension.
  - `:asm`: C kernel with the crowd-sensing scan in hand-written x86-64 assembly (`crowd_x86_64.S`).
- C extension refactored: `kernel_c.c` (pure C kernel on plain buffers) + `world.c` (Ruby glue);
  `World#backend`, `World#kernel_bench` (kernel-only timing, no Ruby).
- Benchmark rewritten: 6 tiers, N fresh-process repeats, median and min-max spread, full-sim
  creatures/sec, generations/sec, per-phase time shares (brains / ISeq compile / world),
  world-loop throughput via Ruby API and kernel-only, crowd-scan ns/creature.
- Correction: the 0.1.0 "world-loop micro" numbers overstated the native tiers. That loop ran
  past MAX_AGE (900 ticks), so most bodies had died while updates were still counted per spawned
  body. The micro now runs 600-tick blocks on fresh worlds and counts live bodies only.
- New selection vs random-drift control (`--control`): same seeds, brains still executed, random
  actions + flat cost in the null arm; common-garden foraging assay; exact permutation test with
  Holm correction; species/opcode entropy and bytecode length.
- `Simulation` gains `control:` (`:selection`/`:drift`) and `prof` (per-phase timers).
- Tests: 4-way backend equivalence, permutation test, Holm, entropy, drift control.

## 0.1.0 (2026-11-21)

- A-Life core: a 768x512 toroidal world of creatures that move, eat, reproduce and die.
  Each creature's brain is a real Ruby lambda compiled with `RubyVM::InstructionSequence`,
  round-tripped through `to_binary`/`load_from_binary`, and installed with `define_method`.
- Body phenotype (hue, size, polygon sides, glow) derived only from the genome's real
  opcode histogram and bytecode length; metabolic cost scales with bytecode length.
- Natural selection events: TracePoint(:call) gene transfer that rewrites a live method
  mid-call, Ractor hive-mind votes, `GC.compact` "enlightenment", `GC.start` "amnesia",
  `prepend` survival instinct, Refinement guardrail, ObjectSpace-sourced mutation constants.
- `ext/yarvpilled_native`: ruby.h-only C extension for the world loop (spatial hash,
  resource field, movement, collision, death) and a software rasterizer.
- Pure-Ruby world port that is bit-identical to the C version (tested).
- Outputs: H.264 MP4 + GIF + PNG stills rendered in-process; ANSI truecolor TUI;
  stdlib TCPServer + SSE browser mode with a canvas renderer.
- Honest 3-tier benchmark (interpreter / YJIT / C ext + YJIT) with identical-work checksum.
- Worked around a YJIT 3.4.7 panic on fixed-arity cfuncs with more than 5 arguments by
  exposing those C entry points as variadic.
