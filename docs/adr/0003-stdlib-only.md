# 0003. Stdlib only, no runtime gems

Date: 2026-11-21. Status: Accepted.

## Context
The demo should run with nothing but a CRuby install, and it should show what the VM alone can do.

## Decision
There are no runtime gems. PNG encoding (Zlib), the HTTP/SSE server (`socket`), the TUI (ANSI),
the rasterizer, and the statistics (exact permutation test, Holm) are all implemented in-tree.
Dev tooling uses only bundled gems (`rake`, `minitest`). External tools are optional: ffmpeg
for video and cargo for the Rust backend.

## Consequences
- There is no Gemfile and nothing to `bundle install`.
- Some code (PNG encoder, statistics) is hand-rolled and covered by tests instead of a library.
