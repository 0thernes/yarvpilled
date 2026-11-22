# Pre-registration: selection vs. random drift, confirmatory run (v0.4.0)

Status: **registered before data collection.** This file and the analysis code in
`lib/yarvpilled/control.rb` are committed before the confirmatory run. The commit that adds the
results must come later in `git log` than the commit that adds this file. To check:
`git log --follow --format='%h %ad %s' -- docs/preregistration.md docs/control.md`.

## Background
A pilot (v0.2.0, seeds 101-108, n = 8 per arm, `docs/control_pilot.md`) suggested selected
populations forage and survive better than a random-drift null model. Pilot seeds are **not
reused**.

## Design (fixed in advance)
- **Arms:** `selection` (brain output drives behaviour; metabolic cost scales with bytecode length)
  vs. `drift` (the brain still executes, but actions are random and cost is flat).
- **Replicates:** n = 20 per arm, seeds **201-220**. Each seed runs once in each arm.
- **Run:** 4000 ticks, events off, `world = native` (C kernel), Ruby 3.4 with `--yjit`.
  Command: `ruby --yjit yarv_brain.rb --control --replicates=20 --first-seed=201 --ticks=4000 --workers=6`.
  The result is deterministic and does not depend on `--workers`.
- **Assay (unchanged from the pilot):** for each population, take the top 8 species by abundance;
  each species gets 40 clones, 300 ticks, flat cost, a fixed arena (`Random.new(1234)`), and no
  reproduction. Results are abundance-weighted.

## Hypotheses
| id | metric | predicted direction | role |
|---|---|---|---|
| H1 | assay fitness (energy intake per creature-tick) | selection > drift | primary |
| H2 | assay survival (fraction alive after 300 ticks) | selection > drift | primary |
| H3 | mean bytecode length (words) | selection < drift | secondary |
| H4 | species entropy (bits) | selection < drift | secondary |
| H5 | opcode entropy (bits) | selection < drift | secondary |
| - | final in-sim population | no prediction | context only |

## Analysis (fixed in advance)
- Two-sided permutation test on the difference of means. With n = 20 per arm there are
  C(40,20) ≈ 1.4e11 relabelings, so the test is Monte Carlo: 100,000 relabelings, seed 7, and
  p = (1 + extreme) / (1 + B), which gives a minimum p of about 1e-5.
- Holm-Bonferroni correction across all 6 metrics (same family as the pilot). α = 0.05.
- Effect sizes: Cohen's d (pooled SD) and the difference of means, each with a 95% percentile
  bootstrap CI (10,000 resamples within each arm, seed 42).
- **Decision rule:** a hypothesis is *supported* if its Holm-adjusted p < 0.05 **and** the sign of
  the difference matches the prediction. Otherwise it is *not supported*, and the README will say so.
- No outlier exclusion, no extra seeds, and no metric changes after the data are seen. Any
  deviation will be listed below with a reason.

## What would count against the claim
H1 or H2 not supported, or reversed. Either would mean "selection measurably beats drift" is not
established at this scale, and the claim would be withdrawn from the README.

## Deviations
- Report formatting only: the first rendering printed p < 0.001 as `0.0000`. The table was
  re-rendered from the same saved rows (`Control.report_from_json`) with scientific notation.
  Data, tests and decisions are unchanged.

## Outcome (added after the run, in a later commit)
H1-H5 are all supported (Holm p ≤ 8e-4, predicted signs). See [control.md](control.md).
