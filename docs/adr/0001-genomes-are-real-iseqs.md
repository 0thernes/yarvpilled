# 0001. Genomes are real YARV instruction sequences

Date: 2026-11-21. Status: Accepted.

## Context
The project's premise is "thinking in YARV". A fake (an interpreter written in Ruby, or a
vector of weights labelled "bytecode") would make every downstream claim decoration.

## Decision
A genome is a small expression tree that renders to Ruby source. It is compiled with
`RubyVM::InstructionSequence.compile`, serialized with `#to_binary`, reloaded with
`load_from_binary(...).eval` into a lambda, and installed with `define_method(:think)` on a
per-species `Class.new(Mind)`. The phenotype and metabolic cost are computed from the real
`iseq.to_a` opcode histogram and bytecode length.

## Consequences
- Creatures run at real YARV/YJIT speed, so brains dominate profiles once the world is native.
- Mutation means recompiling, which shows up as the "births" share in the benchmark.
- `TracePoint(:call).enable(target:)` can hook a live species method mid-call.
- The `to_binary` format is tied to the running Ruby version, so binaries are never persisted
  across runs.
