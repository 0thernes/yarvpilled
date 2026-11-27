# Configuration

Runtime CLI options and environment variables for `yarvpilled` (Build Standard A33).

## Environment variables

| Variable | Default | Effect |
|---|---|---|
| `YARVPILLED_PURE` | unset (`0`) | Set to `1` to force the bit-identical pure-Ruby world and rasterizer even when the C extension is compiled |
| `YP_STRICT` | unset (`0`) | Set to `1` so `rake compile` aborts on native build failure instead of falling back to pure Ruby (used in Linux/macOS CI) |
| `YP_NO_RUST` | unset (`0`) | Set to `1` to skip compiling/linking the Rust world kernel (`ext/yarvpilled_rust`) |
| `PROP_SCALE` | `1` | Multiplier for property-based test case counts (`test/test_properties.rb`, `test/test_differential.rb`) |
| `MT_CPU` | `0` on Windows | Minitest parallel worker count (`test/test_helper.rb` forces `0` on Windows to avoid Ruby 3.4 Ractor/thread deadlock) |
| `LAKE` | auto-detected | Explicit path to the Lean 4 `lake` binary for `test/test_formal_mirror.rb` |
| `REPEATS`, `TICKS` | `5`, `2000` | Override benchmark repeat and tick counts for `rake bench` |
| `REPLICATES`, `FIRST_SEED`, `WORKERS` | `20`, `201`, `nproc` | Override selection-vs-drift control parameters for `rake control` |
| `WHO` | `anonymous` | Replicator label written into `out/replication.json` by `rake replicate` |
| `QUICK` | unset | Set to `1` for a shorter `rake reproduce` run |
| `RECORD` | unset | Set to `1` for `rake sanitize` to update `docs/verification/sanitize.json` |

## CLI flags

- Simulation (`yarv_brain.rb` / `exe/yarvpilled`): `--tui`, `--video`, `--headless`, `--bench`,
  `--control`, `--version`, `--world=native|c|asm|rust|ruby`, `--seed=N`, `--ticks=N`,
  `--seconds=N`, `--fps=N`, `--ticks-per-frame=N`, `--frames=N`, `--repeats=N`, `--replicates=N`,
  `--out=DIR`.
- Browser server (`server.rb`): `--port=N` (default `4567`), `--bind=ADDR` (default `127.0.0.1`),
  `--tps=N`, `--world=KIND`.

No secrets, API keys, or external network services are required to run or verify `yarvpilled`.
