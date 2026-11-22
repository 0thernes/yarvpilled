# Selection vs. random drift (control experiment)

20 seeds x 2 conditions, 4000 ticks each, events off, world=native. Selection: brain output drives behaviour, cost scales with bytecode. Drift (null model): brain still runs, actions are random, cost is flat, so genomes carry no fitness signal. Common-garden assay: top 8 species per population (abundance-weighted), 40 clones each, 300 ticks, flat cost, no reproduction. Seeds 201..220. Test: two-sided permutation test on the difference of means (Monte Carlo, 100000 seeded relabelings of C(40,20) = 137846528820), with Holm-Bonferroni correction across the 6 metrics; 95% percentile bootstrap CIs (10000 resamples within arm, seed 42) for the difference and for Cohen's d. The hand-written seed genome scores fitness 4.438 and survival 0.55 in the same assay.

| metric | selection mean +/- sd | drift mean +/- sd | diff [95% CI] | Cohen's d [95% CI] | permutation p | Holm-adjusted p |
|---|---:|---:|---:|---:|---:|---:|
| assay fitness (energy intake / creature-tick) | 5.073 +/- 0.632 | 4.472 +/- 0.293 | +0.601 [+0.314, +0.909] | 1.22 [0.73, 1.86] | 4.0e-04 | 8.0e-04 |
| assay survival (fraction alive after 300 ticks) | 0.734 +/- 0.166 | 0.566 +/- 0.075 | +0.168 [+0.092, +0.248] | 1.30 [0.82, 1.97] | 1.2e-04 | 3.6e-04 |
| species entropy (bits) | 5.194 +/- 0.407 | 6.126 +/- 0.163 | -0.932 [-1.127, -0.750] | -3.01 [-3.97, -2.50] | 1.0e-05 | 6.0e-05 |
| opcode entropy (bits) | 3.355 +/- 0.060 | 3.611 +/- 0.041 | -0.257 [-0.287, -0.225] | -4.99 [-7.47, -3.84] | 1.0e-05 | 6.0e-05 |
| mean bytecode length (words) | 34.506 +/- 2.995 | 52.411 +/- 6.579 | -17.905 [-21.104, -14.969] | -3.50 [-5.23, -2.73] | 1.0e-05 | 6.0e-05 |
| final population (in-sim, context only) | 214.850 +/- 33.875 | 189.800 +/- 22.867 | +25.050 [+8.450, +43.150] | 0.87 [0.34, 1.46] | 0.0077 | 0.0077 |

Per-replicate rows are in control.json.

The minimum attainable p is 1e-05.

## Run record

- Pre-registration: `docs/preregistration.md`, committed in `316a27f` before this run.
- Command: `ruby --yjit yarv_brain.rb --control --replicates=20 --first-seed=201 --ticks=4000 --workers=6`
  on code at `316a27f`. Took 22.7 s wall time on an 8-vCPU Intel Xeon (Linux, Ruby 3.4.7 + YJIT).
- Outcome against the pre-registered decision rule: **H1 supported, H2 supported, H3 supported,
  H4 supported, H5 supported.** All have Holm p < 0.05 and the predicted sign.
- Pilot (seeds 101-108, n = 8 per arm): [control_pilot.md](control_pilot.md).
