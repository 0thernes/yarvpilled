# 0004. Variadic C entry points to avoid a YJIT 3.4 panic

Date: 2026-11-21. Status: Accepted.

## Context
On Ruby 3.4.7, YJIT panicked (`x86_split: assertion failed: opnds.len() <= C_ARG_OPNDS.len()`)
when it direct-called this extension's fixed-arity C methods that take more than 5 arguments.

## Decision
Every C method with more than 5 Ruby-level arguments is registered with arity `-1`
(`argc, argv`) and checks its own arguments. See the comment in `raster.c`.

## Consequences
- This adds a small argument-checking cost on those calls, which is negligible next to the work they do.
- The code is safe on affected YJIT versions. It can be revisited once the upstream fix is in
  every supported Ruby.
