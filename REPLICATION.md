# Replication

Please try to break this. A replication that fails is more useful than one
that passes. Every deterministic headline number (checksums, state digests,
control-experiment replicates and their statistics) should come out
**bit for bit** the same on your machine.

## One command

```sh
git clone https://github.com/0thernes/yarvpilled && cd yarvpilled
just replicate who="your name"        # or: rake replicate WHO="your name"
```

That does a clean rebuild (`rake clean compile`), runs the whole test suite, then
`tools/reproduce.rb`, which re-runs the benchmark workload on every available backend and
three recorded control replicates per arm, and compares everything with `docs/*.json`. It
writes `out/replication.json` and exits non-zero if anything differs. Expect a few minutes.

Requirements: Ruby 3.3+ (3.4.7 is pinned in `.ruby-version`), a C compiler, optionally cargo
(Rust 1.85.1 is pinned in `rust-toolchain.toml`). No gems.

Optional, slower: `rake bench` (timings; compare ratios, not absolute numbers) and `rake
control` (the full pre-registered experiment, 40 runs).

## Report it

Open a [Replication report](https://github.com/0thernes/yarvpilled/issues/new?template=replication.yml)
and paste `out/replication.json`. Failed checks are especially welcome.

## Replications so far

| # | who | when (UTC) | platform | Ruby | worlds | result | report |
|---|---|---|---|---|---|---|---|
| 1 | dev box (author) | 2026-11-23 | x86_64-linux, 8 vCPU Intel Xeon (container) | 3.4.7 + YJIT | c, asm, rust, ruby | 15/15 bit for bit | `docs/replications/box-ruby34.json` |
| 2 | dev box (author) | 2026-11-23 | x86_64-linux, same box | 3.4.7, `YARVPILLED_PURE=1` | ruby | 9/9 bit for bit | `docs/replications/box-ruby34-pure.json` |
| 3 | author's PC (MSI) | 2026-11-25 | x64-mingw-ucrt, Windows 11, Intel Core Ultra 9 275HX (24 threads) | 3.4.9, no YJIT | ruby (no C compiler installed) | 9/9 bit for bit | `docs/replications/alex-pc-win11-ruby349-pure.json` |
| 4 | GitHub Actions ubuntu-latest | pending | | 3.4 | | run the `Replicate` workflow | artifact |
| 5 | GitHub Actions macos-latest (arm64) | pending | | 3.4 | | run the `Replicate` workflow | artifact |
| 6 | GitHub Actions windows-latest | pending | | 3.4 | | run the `Replicate` workflow | artifact |
| | *you?* | | | | | | |

Entries 1-2 share hardware with the original runs, so they show the numbers are
reproducible from a clean build, not that they are portable. Entry 3 is the first other OS,
CPU, libm and Ruby patch version (run at commit `696778c`, pure Ruby only), but it is still the
author's machine. The CI runners would be the first hardware nobody involved owns; humans on
other machines are what this table is for.
