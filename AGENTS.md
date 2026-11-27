# AGENTS.md

Canonical instructions for every coding agent working in `0thernes/yarvpilled`
(Codex, Claude Code, Gemini CLI, Antigravity, Cursor, Grok, and others).
`CLAUDE.md`, `GEMINI.md`, `.cursor/rules/build-standard.mdc`, and `llms.txt` only point here.
Edit this file, never the pointer files.

## Project

- Name: `yarvpilled`
- Purpose: Zero-model artificial-life simulation in CRuby where every creature's brain is a live `RubyVM::InstructionSequence`, with bit-identical pure-Ruby, C99, Rust, and hand-written x86-64 assembly world kernels, a pre-registered selection-vs-drift control experiment, and a 14-layer verification ladder (Minitest, property/differential tests, ASan/UBSan, libFuzzer, mutation testing, CBMC, Kani, and Lean 4.35.0 proofs of integer step invariants).
- Author: Alexander Stephen Donahue (`0thernes`, ORCID `0009-0006-8168-9648`, `0_0@0thernes.art`, Independent Researcher, Spokane, WA, USA). Never assert `"0thernes LLC"` in any file.
- Manifest: `repo.yaml` (Build Standard for LLMs v1.2.0)
- Single version source: `VERSION` (`0.4.1`, verified by `test/test_project.rb` against `lib/yarvpilled/version.rb`, `CHANGELOG.md`, `CITATION.cff`, `README.md` BibTeX, and `formal/lean/lakefile.toml`)
- Stack: CRuby 3.3 / 3.4 (stdlib only, 0 runtime gems, YJIT-ready), C99 (`ext/yarvpilled_native`), Rust 1.85.1 (`ext/yarvpilled_rust`), x86-64 SysV asm (`crowd_x86_64.S`), Lean 4.35.0 (`formal/lean`), CBMC (`formal/cbmc`)
- License: MIT (see `LICENSE`)
- Status: active

## Layout

- `lib/yarvpilled/`: Pure-Ruby simulation, genome grammar/compiler, world kernel, stats, benchmark, control experiment
- `ext/yarvpilled_native/`: Ruby C extension (`world.c`, `kernel_c.c`, `raster.c`, `crowd_x86_64.S`, `trig_table.h`)
- `ext/yarvpilled_rust/`: Rust world kernel (`src/lib.rs`, `src/proofs.rs` with 7 Kani harnesses)
- `formal/lean/`: Lean 4.35.0 spec (`Yarvpilled/Spec.lean`, `Yarvpilled/Slots.lean`, `Mirror.lean`, `VerifyAxioms.lean`, `check.sh`)
- `formal/cbmc/`: CBMC bounded model checking harnesses and exhaustive lattice checker
- `test/`: Minitest suite (`test_claims.rb`, `test_project.rb`, `test_properties.rb`, `test_differential.rb`, `test_formal_mirror.rb`, `test_world_equivalence.rb`, `test_negative.rb`, etc.)
- `tools/`: Verification/reproduction runners (`claims.rb`, `reproduce.rb`, `mutate.rb`, `genome_fuzz.rb`, `release_notes.rb`, `build_site.rb`)
- `docs/`: Architecture, ADRs, benchmarks, control results, verification ladder, and replication logs

## Commands

Run from the repository root (`Rakefile` and `justfile` expose matching recipes):

- Compile native extension (falls back to pure Ruby on failure): `rake compile` (`YP_STRICT=1` makes native build failure fatal)
- Run Minitest suite: `rake test` (or `RUBYOPT=--yjit rake test`, or `YARVPILLED_PURE=1 rake test`)
- Check README generated blocks against recorded JSON data: `ruby tools/claims.rb` (`--write` to regenerate)
- Clean rebuild + tests + deterministic headline reproduction: `rake reproduce` (or `just reproduce`)
- Lean 4 build, axiom audit, kernel replay, and mirror differential test:
  - `cd formal/lean && lake build && lake env lean VerifyAxioms.lean && lake env leanchecker --fresh Yarvpilled`
  - `ruby -Ilib -Itest test/test_formal_mirror.rb`
  - On Unix/CI: `formal/lean/check.sh`
- Static checks (informational): `rake lint`

## Hard rules (Build Standard v1.2.0)

- R1. Nothing may gate, block, or slow a commit or push. No branch protection, no required status checks, no commit/tag signing requirements, no git hooks, no push protection, no merge queues, and no blocking SAST/coverage gates.
- R2. Commit and push straight to `main`. No pull requests and no feature branches. Fixes for failing checks are follow-up commits to `main`.
- R3. CI is informational. A red CI run is a finding to fix, never a barrier.
- R4. Banned tools and files: no `.github/dependabot.yml`, no Renovate config, no PR templates, no `.coderabbit.yaml`, no Copilot review or `.github/copilot-instructions.md`, no `FUNDING.yml` unless the owner asks.
- R5. One-person lean, not corporate. Prefer one file over a framework and one command over a checklist.
- R6. Never fabricate. Every number in `README.md` and `docs/verification.md` is computed from `docs/*.json` by `tools/claims.rb` and checked by `test/test_claims.rb`. Never claim unproven floating-point properties in Lean or unrun Kani/CBMC results.
- R7. Classify every finding as exactly one of: `bug`, `error`, `issue`, `problem`, `concern`, `dilemma`, `conflict`, `gap`, `hole`, `blindspot`.
- R8. Precedence when rules collide: owner's explicit instruction, then R1–R8, then Build Standard v1.2.0 items, then ecosystem conventions.

## Finding classes

- `bug`: Defect in program logic (code runs but diverges from spec/intent).
- `error`: Wrong artifact or failed execution outside program logic (wrong number, claim, doc, config, version, build, or command).
- `issue`: Weakness in something that exists (works and not wrong, but unclear, inconsistent, fragile, or hard to maintain).
- `problem`: External obstacle blocking progress not caused by this project's own code/artifacts.
- `concern`: Risk that has not caused harm yet (future failure, misleading wording, cost, security/legal exposure).
- `dilemma`: Trade-off between valid options depending on owner priorities.
- `conflict`: Two requirements, sources, or rules contradict each other.
- `gap`: Something required or expected is missing, while nothing present is wrong.
- `hole`: Missing check or safeguard that could let a defect slip through unnoticed.
- `blindspot`: Unexamined user, platform, failure mode, or assumption.

## Known traps

- **`test_claims.rb` strict checks:** `test_readme_badges_match_their_counts` parses `^theorem ` in `formal/lean/Yarvpilled/*.lean` (must stay at column 0 — use `public section` rather than prefixing `public theorem`), counts `| C-... |` rows in `CLAIMS.md`, and checks `docs/verification.md` status counts against `README.md`. `test_claim_map_resolves` verifies every backticked `test_*.rb` / `formal/*` / `tools/*` path in `CLAIMS.md` exists on disk.
- **`test_project.rb` version & YAML checks:** `VERSION`, `CHANGELOG.md`, `CITATION.cff`, `README.md` BibTeX, and `formal/lean/lakefile.toml` must all agree on `Yarvpilled::VERSION`, and all `.github/**/*.yml` + `CITATION.cff` must parse cleanly with `YAML.safe_load_file`.
- **Windows checkout paths with `[ ]`:** Always use `Dir.glob(..., base: ...)` in Ruby (never raw `Dir[]` on paths containing `[Vibe Coded (AI)]`), and `-LiteralPath` in PowerShell.
- **Windows Lean PATH:** Prepend `C:\Users\Alexa\.elan\bin` to `PATH` when invoking `lake`/`lean` or running `test_formal_mirror.rb`. Note `lake check --paranoid` requires Linux `bwrap`; on Windows run `lake build`, `lake env lean VerifyAxioms.lean`, and `lake env leanchecker --fresh Yarvpilled`.
- **Windows Minitest + Ractor:** `test/test_helper.rb` sets `MT_CPU=0` on Windows to prevent Ruby 3.4 parallel-executor deadlock with Ractors.
- **Variadic C functions for YJIT:** Keep >5-arg Ruby C entry points variadic (`argc, argv`) to avoid the Ruby 3.4.7 YJIT `x86_split` panic.
