# Selection vs. random drift (control experiment)

8 seeds x 2 conditions, 4000 ticks each, events off, world=native. Selection: brain output drives behaviour, cost scales with bytecode. Drift (null model): brain still runs, actions are random, cost is flat, so genomes carry no fitness signal. Common-garden assay: top 8 species per population (abundance-weighted), 40 clones each, 300 ticks, flat cost, no reproduction. Test: exact two-sided permutation test on the difference of means (all C(16,8) = 12870 relabelings), with Holm-Bonferroni correction across the 6 metrics. The hand-written seed genome scores fitness 4.438 and survival 0.55 in the same assay.

| metric | selection mean +/- sd | drift mean +/- sd | diff | Cohen's d | permutation p | Holm-adjusted p |
|---|---:|---:|---:|---:|---:|---:|
| assay fitness (energy intake / creature-tick) | 5.009 +/- 0.472 | 4.417 +/- 0.410 | +0.592 | 1.34 | 0.0190 | 0.0379 |
| assay survival (fraction alive after 300 ticks) | 0.708 +/- 0.114 | 0.512 +/- 0.090 | +0.196 | 1.91 | 0.0030 | 0.0089 |
| species entropy (bits) | 5.209 +/- 0.327 | 6.040 +/- 0.196 | -0.831 | -3.08 | 0.0002 | 0.0009 |
| opcode entropy (bits) | 3.286 +/- 0.191 | 3.642 +/- 0.063 | -0.357 | -2.50 | 0.0002 | 0.0009 |
| mean bytecode length (words) | 32.523 +/- 7.740 | 54.176 +/- 6.850 | -21.652 | -2.96 | 0.0002 | 0.0009 |
| final population (in-sim, context only) | 209.500 +/- 29.394 | 182.250 +/- 21.110 | +27.250 | 1.06 | 0.0485 | 0.0485 |

Per-replicate rows are in control.json.
