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

# selection vs drift control -> out/control.md
control replicates="8" ticks="4000":
    ruby --yjit yarv_brain.rb --control --replicates={{replicates}} --ticks={{ticks}}

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
