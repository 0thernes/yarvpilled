# Roadmap

Direction, not promises. A solo hobby project: things land when they're fun and honest.

## Next (0.4)
- **Brains under YJIT:** profile genome ISeqs with `--yjit-stats` and find which opcodes
  dominate. Brains are about 70% of each tick once the world is native.
- **Cheaper births:** cache compiled ISeqs for identical mutated sources. Genome compilation is
  about 13% of a tick.
- **Windows native build:** confirm the C extension under the RubyInstaller DevKit in CI and drop
  `continue-on-error` once it is green.
- **Bigger control experiment:** more seeds, a second assay arena, and longer runs (50+ generations).

## Later
- Rust backend on Windows (MSVC/GNU target selection in the Rakefile).
- An aarch64 NEON or SVE crowd-scan experiment, if a data layout can stay bit-identical.
- An in-browser live mode via ruby.wasm, running the real simulation instead of a replay.
- Publish the gem to RubyGems once the CLI and options are stable.

## Not planned
- Neural nets or ML libraries. Brains stay YARV bytecode.
- Runtime gem dependencies.
- Anything that adds process friction (required checks, mandatory signing, commit hooks).
