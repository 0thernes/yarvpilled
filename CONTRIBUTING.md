# Contributing

Issues and PRs are welcome. Keep it small and keep it honest.

```sh
rake compile && rake test      # or: just
RUBYOPT=--yjit rake test
YARVPILLED_PURE=1 rake test    # pure-Ruby fallback
rake smoke
```

Three rules:

1. **Real vs. metaphor.** If something claims to use a VM mechanism, it really does. Update
   the README table when you add one.
2. **The world never thinks, and backends stay bit-identical.** World-loop changes go into
   all four backends (`kernel_c.c`, `crowd_x86_64.S`, `ext/yarvpilled_rust`, `world_ruby.rb`).
   `test_world_equivalence.rb` checks this.
3. **Numbers are medians over fresh processes** (`rake bench`), never single runs.

Stdlib only, no runtime gems. Add a line under `[Unreleased]` in `CHANGELOG.md`. CI is
informational and never blocks a merge.

To release: bump `VERSION` and `lib/yarvpilled/version.rb`, move the Unreleased notes into a
version section, then `git tag -a vX.Y.Z -m vX.Y.Z && git push --follow-tags`. The Release
workflow publishes the notes.

By contributing you agree to the [MIT License](LICENSE) and the [Code of Conduct](CODE_OF_CONDUCT.md).
