#!/usr/bin/env ruby
# frozen_string_literal: true

# YARVPILLED // pure ISeq cognition // zero models
#
#   ruby --yjit yarv_brain.rb --video            # render out/yarvpilled.mp4 (+ stills, gif, run_log)
#   ruby --yjit yarv_brain.rb --tui              # live ANSI truecolor terminal mode
#   ruby --yjit yarv_brain.rb --headless         # run and print stats
#   ruby yarv_brain.rb --bench                   # Ruby/YJIT/C/Rust/asm benchmark (spawns tier processes)
#   ruby server.rb                               # live browser mode (SSE)

$LOAD_PATH.unshift File.join(__dir__, "lib")
Warning[:experimental] = false
require "optparse"
require "fileutils"
require "etc"
require "yarvpilled"

opts = { mode: :headless, world: Yarvpilled::Native::AVAILABLE ? :native : :ruby, seed: 11, seconds: 40, fps: 30,
         tpf: 2, ticks: 1500, out: File.join(Dir.pwd, "out"), frames: nil }
OptionParser.new do |o|
  o.banner = "usage: ruby [--yjit] yarv_brain.rb [mode] [options]"
  o.on("--video", "render MP4 + GIF + stills + run log") { opts[:mode] = :video }
  o.on("--tui", "live terminal mode") { opts[:mode] = :tui }
  o.on("--headless", "simulate and print stats (default)") { opts[:mode] = :headless }
  o.on("--bench", "benchmark every available tier") { opts[:mode] = :bench }
  o.on("--bench-tier", "(internal) run one tier") { opts[:mode] = :bench_tier }
  o.on("--control", "selection vs drift control experiment") { opts[:mode] = :control }
  o.on("--replicates=N", Integer, "control: seeds per condition (default 8)") { opts[:replicates] = _1 }
  o.on("--repeats=N", Integer, "bench: runs per tier (default 5)") { opts[:repeats] = _1 }
  o.on("--world=KIND", %w[native c asm rust ruby], "native/c, asm, rust (C ext backends) or ruby") { opts[:world] = _1.to_sym }
  o.on("--seed=N", Integer) { opts[:seed] = _1 }
  o.on("--seconds=N", Integer, "video length") { opts[:seconds] = _1 }
  o.on("--fps=N", Integer) { opts[:fps] = _1 }
  o.on("--ticks-per-frame=N", Integer) { opts[:tpf] = _1 }
  o.on("--ticks=N", Integer, "headless/bench ticks") { opts[:ticks] = _1 }
  o.on("--frames=N", Integer, "TUI: stop after N frames") { opts[:frames] = _1 }
  o.on("--out=DIR") { opts[:out] = _1 }
  o.on("-v", "--version", "print version and available world backends") do
    kinds = Yarvpilled::World::KINDS.select { Yarvpilled::World.available?(_1) }
    puts "yarvpilled #{Yarvpilled::VERSION} (ruby #{RUBY_VERSION}, worlds: #{kinds.join(', ')})"
    exit
  end
end.parse!

FileUtils.mkdir_p(opts[:out])

case opts[:mode]
when :bench_tier
  puts JSON.generate(Yarvpilled::Bench.run_tier(world: opts[:world], ticks: opts[:ticks], seed: opts[:seed]))
when :bench
  puts Yarvpilled::Bench.run_all(ticks: opts[:ticks], seed: opts[:seed], out_dir: opts[:out], repeats: opts[:repeats] || 5)
when :control
  puts Yarvpilled::Control.run(replicates: opts[:replicates] || 8, ticks: opts[:ticks], out_dir: opts[:out])
when :tui
  sim = Yarvpilled::Simulation.new(seed: opts[:seed], world: opts[:world])
  Yarvpilled::TUI.new(sim).run(frames: opts[:frames], ticks_per_frame: 1)
  sim.close
when :video
  Yarvpilled::Video.new(opts).run
else
  sim = Yarvpilled::Simulation.new(seed: opts[:seed], world: opts[:world], log: $stdout)
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  opts[:ticks].times { sim.step! }
  dt = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
  puts format("\n%d ticks in %.2fs | gen %d | births %d | species ever %d | alive %d | rewrites %d | compacts %d | think() calls %d",
              sim.tick, dt, sim.max_gen, sim.births_total, sim.species.size, sim.alive_count, sim.rewrites_total, sim.compacts, sim.think_calls)
  sim.close
end
