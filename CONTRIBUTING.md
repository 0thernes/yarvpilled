# Contributing to yarvpilled

Thanks for taking a look. This is a small, opinionated project: an A-Life world whose
creatures think in real YARV bytecode. Contributions that keep it **honest** (real VM
mechanics, clearly labelled metaphors, reproducible numbers) are very welcome.

## Ground rules

- **Stdlib only.** No runtime gems. Dev tooling is `rake` + `minitest`, both bundled with CRuby.
- **Real vs. metaphor.** If a feature claims to use a VM mechanism, it must actually use it.
  Update the real-vs-metaphor table in the README whenever you add or change one.
- **The world never thinks.** Native kernels (C / Rust / asm) only move bodies. Every decision
  comes from YARV executing a genome ISeq.
- **Backends stay bit-identical.** Any change to the world loop must be made to all four
  backends (`kernel_c.c`, `crowd_x86_64.S`, `ext/yarvpilled_rust/src/lib.rs`,
  `lib/yarvpilled/world_ruby.rb`) with the same IEEE-754 operation order.
  `test/test_world_equivalence.rb` enforces this.
- **Benchmarks are reproducible.** Report median and spread over fresh processes
  (`rake bench`), and never quote a single run.

## Setup

```sh
git clone https://github.com/0thernes/yarvpilled && cd yarvpilled
rake compile          # C ext + asm + Rust (Rust only if cargo is installed)
rake test             # interpreter
RUBYOPT=--yjit rake test
YARVPILLED_PURE=1 rake test   # pure-Ruby fallback path
rake smoke            # 300-tick headless run
```

Use `YP_STRICT=1 rake compile` while working on the extension, so build failures are
fatal instead of silently falling back to pure Ruby.

## Making a change

1. Open an issue first for anything larger than a bug fix, so we can agree on the approach.
2. Keep commits focused, and write messages in the imperative ("Add X", "Fix Y").
3. Add or update tests. New world-loop behaviour needs an equivalence test across backends.
4. Run the full test matrix above, plus `rake smoke`.
5. Add an entry under `## [Unreleased]` in `CHANGELOG.md`
   ([Keep a Changelog](https://keepachangelog.com/en/1.1.0/) style).
6. For architectural decisions, add an ADR in `docs/adr/` (copy the format of an existing one).

## Style

- Ruby: 2-space indent, `# frozen_string_literal: true`, small methods, and comments that
  explain *why*.
- C: C99/gnu99, ruby.h public API only (no internal headers), `-Wall -Wextra` clean.
- Rust: `cargo fmt`, no external crates, `#[repr(C)]` layout mirrors `world.h` exactly.
- `.editorconfig` covers whitespace.

## Releases (maintainers)

1. Bump `VERSION` and `lib/yarvpilled/version.rb` (the release workflow checks they match the tag).
2. Move `[Unreleased]` notes to a new version section in `CHANGELOG.md`.
3. `git tag -a vX.Y.Z -m "vX.Y.Z" && git push origin main --tags`.
   The Release workflow creates the GitHub Release from the CHANGELOG section.

By contributing you agree that your contributions are licensed under the MIT License and that
you will follow the [Code of Conduct](CODE_OF_CONDUCT.md).
