# Claims

Every claim the README makes, with the command that produces it and the test
that would fail if it stopped being true. Numbers in the README sit inside
generated blocks (`<!-- generated:... -->`) that `tools/claims.rb` computes from
`docs/*.json`; `test/test_claims.rb` fails if any of them drift from the data.

Deterministic claims are re-derived bit for bit by `just reproduce` /
`ruby tools/reproduce.rb`. Timing claims are not bit-reproducible; re-measure
them with `rake bench` and compare shapes (ratios, rankings within noise).

| ID | claim | produced by | checked by |
|---|---|---|---|
| C-EQ-1 | The C, asm, Rust and pure-Ruby world backends are bit-identical, step by step. | — | `test_world_equivalence.rb` (300 ticks with births), `test_differential.rb` (300 random worlds vs a slow reference stepper), `fuzz/run.sh` (C vs asm vs Rust, 4.3M worlds), `formal/cbmc/lattice.sh` (asm crowd and Rust tick vs C on every placement of a 3-unit lattice, 5.3M ticks) |
| C-EQ-2 | The integer part of the step matches a Lean 4 model with proved invariants. | `formal/lean/Mirror.lean` | `test_formal_mirror.rb` (1500 scenarios x every backend) |
| C-REAL-1 | Each brain is a real YARV ISeq: compile, `to_binary`, `load_from_binary`, `define_method`. | `Genome#compile!` | `test_genome.rb` (`test_seed_compiles_to_a_real_iseq_and_behaves`, `test_binary_roundtrip_is_the_genome`) |
| C-REAL-2 | Body traits come only from the bytecode (opcode histogram, length). | `Genome#traits` | `test_genome.rb` (`test_traits_derive_only_from_bytecode`, `test_histogram_and_length_match_the_disasm`) |
| C-REAL-3 | A TracePoint rewrites a live method mid-call. | `Simulation#arm_gene_transfer!` | `test_simulation.rb` (`test_tracepoint_rewrites_a_live_method_mid_call`) |
| C-REAL-4 | Ractors, Fibers and GC.compact actually run. | `Simulation` | `test_simulation.rb` (`test_events_ractors_and_gc_compact_happen_for_real`) |
| C-REAL-5 | The action clamp is a lexically scoped refinement. | `Guardrails` | `test_simulation.rb` (`test_guardrail_refinement_is_lexically_scoped`) |
| C-DET-1 | With events off, a run is a pure function of its seed. | `Simulation` | `test_simulation.rb` (`test_core_is_deterministic_without_events`), `test_properties.rb` (`test_determinism`), `tools/reproduce.rb` |
| C-BENCH-1 | Every benchmark run of every tier did identical work: one full-sim checksum. | `rake bench` → `docs/bench.json` | `tools/reproduce.rb` (re-runs seed 11 on every backend), `test_claims.rb` |
| C-BENCH-2 | Every world-loop timing ended on the same state digest. | `rake bench` → `docs/bench.json` | `tools/reproduce.rb`, `test_claims.rb` |
| C-BENCH-3 | Native tiers are about 3.3-3.5x pure Ruby end to end and tied with each other within run-to-run noise. | `rake bench` | README block `speed-glance` / `bench-verdict` = `docs/bench.json` (`test_claims.rb`); re-measure with `rake bench` |
| C-BENCH-4 | About 70% of a native tick is YARV running genome bytecode. | `rake bench` (in-process phase timers) | as C-BENCH-3 |
| C-BENCH-5 | The native world loop is about 18-22x the pure-Ruby one through the Ruby API. | `rake bench` | as C-BENCH-3 |
| C-BENCH-6 | The hand-written asm crowd scan is in the same range as gcc -O3, not a big win. | `rake bench` | as C-BENCH-3 |
| C-CTRL-1 | Every recorded control replicate re-runs to the same metrics, bit for bit. | `rake control` → `docs/control.json` | `tools/reproduce.rb` (seeds 201-203, both arms) |
| C-CTRL-2 | Selection beats drift on assay fitness and survival, purges bytecode and lowers entropy (Holm p < 0.05, n = 20 per arm). | `rake control` | `test_claims.rb` (summary stats recomputed from rows), `tools/reproduce.rb` (permutation p recomputed), `test_stats.rb` (the statistics themselves) |
| C-CTRL-3 | The confirmatory run's plan was committed before its results (git commit order; git cannot show when the run itself happened). | `docs/preregistration.md` | `test_claims.rb` (git: the pre-registration commit is an ancestor of the results commit) |
| C-INV-1 | Energy accounting: per creature, Δenergy = take + take/2 − metabolism; takes sum to Δeaten; food is conserved up to death refunds. | — | `test_properties.rb` (`test_energy_accounting`, 1500 worlds), Lean `energy_identity_sum`, Kani `metabolize_identity_no_overflow` (Kani runs in CI only; its 20,000-case randomized twin runs locally) |
| C-INV-2 | Positions stay on the torus, headings in 0..63, sensors in range, population ≤ capacity. | — | `test_properties.rb` (`test_bounds_hold_on_every_backend`), Lean `population_le_cap`, CBMC `h_wrapd_into_torus` / `h_food_index_*` / `h_crowd_bounded` (`formal/cbmc/check.sh`; the whole-tick harness `h_act_tick_safe` did not finish, see docs/verification/cbmc.json), `formal/cbmc/lattice.sh`, fuzzer range checks |
| C-INV-3 | Mutation never produces a genome its own grammar rejects; every brain returns an Integer and survives the binary round trip. | `Genome#mutate` | `test_properties.rb` (`test_mutation_chains_always_yield_valid_brains`), `tools/genome_fuzz.rb` |
| C-NEG-1 | Bad world parameters and spawn positions are rejected with ArgumentError on every backend. | `World.new`, `#spawn` | `test_negative.rb` |
| C-NEG-2 | Genomes outside the grammar raise InvalidGenome before rendering or compiling. | `Genome.validate!` | `test_negative.rb`, `test_properties.rb` (`test_random_trees_validate_or_reject_cleanly`), `tools/genome_fuzz.rb` |
| C-NEG-3 | Bad CLI arguments exit 2 with a one-line usage error. | `yarv_brain.rb` | `test_negative.rb` (`test_bad_cli_args_exit_2`) |
| C-VER-1 | The verification numbers in docs/verification.md come from recorded runs. | `fuzz/run.sh`, `tools/genome_fuzz.rb`, `tools/mutate.rb`, `RECORD=1 rake sanitize`, `formal/lean/check.sh` | `test_claims.rb` (block `verification-evidence`) |
| C-VER-2 | The C kernel's food-index wrap, torus wrap, short-way delta and crowd scan are memory-safe and overflow-free on the domains of the 5 CBMC harnesses that finished, and no recorded verification run hides a failure (unfinished runs are recorded as TIMEOUT or KILLED, never as passes). | `formal/cbmc/check.sh`, `formal/cbmc/lattice.sh` | `test_claims.rb` (`test_recorded_verification_runs_passed`) |

What these claims do **not** cover, and what would falsify them: [LIMITATIONS.md](LIMITATIONS.md).
