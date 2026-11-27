# Lean 4 spec of the integer step

Core Lean only (no Mathlib), pinned in `lean-toolchain` (v4.35.0).

```sh
./check.sh                                    # build + VerifyAxioms.lean + leanchecker --fresh Yarvpilled
lake build && lake env lean VerifyAxioms.lean # standalone axiom audit (31 theorems)
ruby -Itest ../../test/test_formal_mirror.rb  # backends vs the executable Lean mirror
```

| file | what it proves |
|---|---|
| `Yarvpilled/Spec.lean` | regrowth bounds and exactness, eating conserves food, energy accounting identity (per creature and summed over a population), `take + take/2` injective, death refund bounds, sensor clamps and monotonicity, the asm branch-free grid wrap equals C's `%` on its input range, and invariants of `tick1` (one creature alone in one food cell) |
| `Yarvpilled/Slots.lean` | slot allocation: spawn never exceeds capacity, adds exactly one living creature, and fails when full (population bound) |
| `VerifyAxioms.lean` | `#print axioms` audit for all 31 theorems (strictly within `[propext, Classical.choice, Quot.sound]`, zero `sorry`/`admit`/`native_decide`) |
| `Mirror.lean` | an executable that runs `tick1`; the Ruby test drives every backend through the same scenarios and compares tick by tick |

## The gap, stated plainly

The proofs are about the integer bookkeeping only. Positions, headings, trig,
crowding and collisions use IEEE-754 doubles and are not modelled in Lean.
`tick1` matches the backends only in a world with one food cell, where
movement cannot change which cell a creature eats from. The bridge between the
proved model and the shipped C/asm/Rust/Ruby code is the differential test, not
a proof of the C code itself. Determinism is by construction in Lean (pure
functions); for the real backends it is tested (`test_properties.rb`).
