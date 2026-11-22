# 0005. Benchmark methodology: fresh processes, median and spread, fixed work

Date: 2026-11-21. Status: Accepted.

## Context
0.1.0 quoted a single-run world-loop micro benchmark, and it was wrong: it ran past the
900-tick lifespan, so most bodies were dead while updates were still counted. YJIT also can't be
turned off inside a process once it's on.

## Decision
- Each tier runs in its own fresh `ruby` process (with or without `--yjit`), N times (default 5).
  Reports give the median, min-max range and spread.
- In the full simulation, events are off and the seed is fixed. Every tier must produce the same
  checksum (births-maxgen-alive-food_eaten-species), which proves identical work.
- The world-only benchmark uses fresh worlds in 600-tick blocks, well under `MAX_AGE`, and
  counts live bodies only. It's measured both through the Ruby API (with glue) and kernel-only.
- Per-phase shares (sense / brains / act / births) come from in-process monotonic timers.

## Consequences
- The claims hold up: when the native backends land within each other's spread, that's
  reported as a tie.
- The full benchmark takes about 2 minutes.
