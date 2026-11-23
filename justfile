# yarvpilled task runner: thin wrappers over rake and the CLI (`just --list`).
# Works on Linux, macOS and Windows (PowerShell).
set windows-shell := ["powershell.exe", "-NoLogo", "-NoProfile", "-Command"]

# compile + test
default: compile test

# build the C extension (+asm, +Rust); falls back to pure Ruby on failure
compile:
    rake compile

# minitest suite (interpreter)
test:
    rake test

# minitest suite with YJIT
test-yjit:
    ruby --yjit -S rake test

# 300-tick headless run
smoke:
    rake smoke

# live ANSI truecolor terminal
tui:
    ruby --yjit yarv_brain.rb --tui

# live browser mode on http://localhost:4567/
serve port="4567":
    ruby --yjit server.rb --port={{port}}

# render out/yarvpilled.mp4 + gif + stills (needs ffmpeg)
video:
    rake video

# benchmark every available tier -> out/bench.md
bench repeats="5" ticks="2000":
    ruby yarv_brain.rb --bench --repeats={{repeats}} --ticks={{ticks}}

# selection vs drift control, the pre-registered run -> out/control.md
control replicates="20" first_seed="201" ticks="4000" workers="4":
    ruby --yjit yarv_brain.rb --control --replicates={{replicates}} --first-seed={{first_seed}} --ticks={{ticks}} --workers={{workers}}

# build the GitHub Pages demo into _site/
site:
    rake site

# build pkg/yarvpilled-VERSION.gem
gem:
    rake gem

# sync GitHub issue labels via gh
labels:
    rake labels

# remove build products
clean:
    rake clean

# ---- verification ladder (docs/verification.md) ----

# clean rebuild + tests + re-derive every deterministic headline number
reproduce:
    rake reproduce

# reproduce, then write out/replication.json for a replication issue
replicate who="anonymous":
    rake replicate WHO="{{who}}"

# README numbers vs docs/*.json (use `ruby tools/claims.rb --write` after a new run)
claims:
    ruby tools/claims.rb

# -Wall -Wextra, clippy, ruby -w (informational)
lint:
    rake lint

# property tests at 10x the cases (Linux/macOS shell)
soak scale="10":
    PROP_SCALE={{scale}} ruby -Itest -e 'ARGV.each { require File.expand_path(_1) }' test/test_properties.rb test/test_differential.rb

# whole suite against an ASan + UBSan build of the C extension (Linux)
sanitize:
    rake sanitize

# libFuzzer differential kernel fuzzer, N seconds (needs clang)
fuzz seconds="600":
    fuzz/run.sh {{seconds}}

# genome fuzzer, N seconds
fuzz-genomes seconds="600":
    ruby tools/genome_fuzz.rb --seconds={{seconds}}

# mutation testing -> docs/verification/mutation.json
mutate:
    ruby tools/mutate.rb

# Lean 4 proofs + backends vs the Lean mirror (needs elan)
prove:
    formal/lean/check.sh
    ruby -Itest test/test_formal_mirror.rb

# randomized runs of the Kani harness bodies (stable Rust); `cargo kani` needs Kani installed
proof-check:
    cd ext/yarvpilled_rust && cargo test --features proof-check
