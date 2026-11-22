# Changelog

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
