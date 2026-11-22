# 0002. The native world never thinks; all backends are bit-identical

Date: 2026-11-21. Status: Accepted.

## Context
Moving the world loop to C, Rust or asm could quietly move "intelligence" out of YARV, or
change the simulation in ways that make the backends incomparable.

## Decision
Native kernels only do physics and bookkeeping: spatial hash, regrowth, movement, eating,
metabolism, collisions, deaths and birth thresholds. Actions always arrive from Ruby. All four
backends use the same integer and IEEE-754 operation order: no FMA (`-ffp-contract=off`),
shared cos/sin tables, and the same iteration order. `world.c` is the one shared Ruby glue
layer.

## Consequences
- `test/test_world_equivalence.rb` can assert bit-identity after every tick, and benchmarks can
  check identical work through a checksum.
- Any change to the world must be made in four places.
- The pure-Ruby backend is always a valid fallback, for example on Windows without a toolchain.
