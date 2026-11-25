# 0006. Random-drift null model for the selection claim

Date: 2026-11-21. Status: Accepted.

## Context
"The population evolves" could just be mutation noise. A claim of selection needs a control
that differs only in whether genomes affect fitness.

## Decision
`Simulation.new(control: :drift)` keeps the seeds, mutation rate and VM work identical (the
brain still executes), but replaces each action with a random one and makes metabolic cost flat.
After N ticks, the top species of each population (abundance-weighted) are measured in a
common-garden foraging assay: 40 clones, 300 ticks, flat cost, no reproduction. The two arms
are compared with an exact two-sided permutation test and Holm-Bonferroni correction across
metrics.

## Consequences
- The README can make a quantified selection claim, with its caveats (n = 8 per arm, one
  arena, about 10 generations).
- The exact test's p-value floor is 2/C(16,8) = 0.000155 with 8 replicates per arm.

## Update (0.4.0)
The numbers above describe the 8-seed pilot (`docs/control_pilot.md`). The confirmatory run
was pre-registered (`docs/preregistration.md`): n = 20 per arm, seeds 201-220, 4000 ticks.
With C(40,20) ≈ 1.4e11 relabelings the test there is a Monte Carlo permutation test (100,000
relabelings, seed 7) with Holm correction, not an exact one. The README quotes that run.
