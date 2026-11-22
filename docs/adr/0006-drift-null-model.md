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
