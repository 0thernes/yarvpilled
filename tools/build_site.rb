#!/usr/bin/env ruby
# frozen_string_literal: true

# Builds the static GitHub Pages demo into _site/ (or the dir given as ARGV[0]):
#   _site/index.html          public/index.html in replay mode
#   _site/replay.ndjson.gz    one line of metadata, then one Telemetry frame per tick
#                             recorded from a real Simulation run in this process
#   _site/social-preview.png  copied from docs/ (for link unfurls)
#
#   ruby --yjit tools/build_site.rb [_site] [--ticks=900] [--seed=11]
#
# The recording is generated in CI (.github/workflows/pages.yml), never committed.

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
Warning[:experimental] = false
require "yarvpilled"
require "zlib"
require "json"
require "fileutils"
require "time"

root = File.expand_path("..", __dir__)
args = ARGV.reject { _1.start_with?("--") }
opt = ARGV.grep(/\A--\w+=/).to_h { k, v = _1.delete_prefix("--").split("=", 2); [k.to_sym, Integer(v)] }
out = File.expand_path(args.first || "_site", root)
ticks = opt.fetch(:ticks, 900)
seed = opt.fetch(:seed, 11)
FileUtils.mkdir_p(out)

sim = Yarvpilled::Simulation.new(seed: seed)
meta = { ruby: RUBY_VERSION, yjit: defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled? ? true : false,
         world: sim.world_impl, seed: seed, ticks: ticks, tps: 20, version: Yarvpilled::VERSION,
         recorded: Time.now.utc.strftime("%Y-%m-%d"), repo: "https://github.com/0thernes/yarvpilled" }
Zlib::GzipWriter.open(File.join(out, "replay.ndjson.gz"), 9) do |gz|
  gz.puts JSON.generate(meta)
  ticks.times do
    sim.step!
    gz.puts Yarvpilled::Telemetry.to_json(sim, full: sim.tick == 1)
  end
end
sim.close

html = File.read(File.join(root, "public/index.html"))
head = <<~HTML
  <meta name="description" content="An A-Life world where every creature's brain is a live YARV bytecode method. Recorded from a real CRuby run.">
  <meta property="og:title" content="YARVPILLED: pure ISeq cognition, zero models">
  <meta property="og:description" content="Every creature's brain is a live RubyVM::InstructionSequence. World loop in Ruby, C, Rust or x86-64 asm.">
  <meta property="og:image" content="social-preview.png">
  <script>window.YP_REPLAY = "replay.ndjson.gz";</script>
HTML
File.write(File.join(out, "index.html"), html.sub("</head>", "#{head}</head>"))
preview = File.join(root, "docs/social-preview.png")
FileUtils.cp(preview, out) if File.exist?(preview)
File.write(File.join(out, ".nojekyll"), "")
size = File.size(File.join(out, "replay.ndjson.gz"))
puts "built #{out} (#{ticks} ticks, replay #{(size / 1e6).round(1)} MB, world=#{meta[:world]}, yjit=#{meta[:yjit]})"
