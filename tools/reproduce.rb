#!/usr/bin/env ruby
# frozen_string_literal: true

# Reproduces the deterministic parts of every headline claim and compares them
# bit-for-bit with the recorded data in docs/. Timings are NOT compared (they're
# hardware-dependent); everything that is deterministic is.
#
#   ruby --yjit tools/reproduce.rb [--quick] [--out=out/replication.json] [--who="name"]
#
# Exit status 0 = every check matched. The JSON report is what goes into
# REPLICATION.md / a replication issue.

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
Warning[:experimental] = false
require "yarvpilled"
require "json"
require "rbconfig"
require "etc"
require "fileutils"

ROOT = File.expand_path("..", __dir__)
quick = ARGV.include?("--quick")
out = ARGV.find { _1.start_with?("--out=") }&.split("=", 2)&.last || File.join(Dir.pwd, "out", "replication.json")
who = ARGV.find { _1.start_with?("--who=") }&.split("=", 2)&.last || ENV.fetch("YP_REPLICATOR", "anonymous")

bench = JSON.parse(File.read(File.join(ROOT, "docs/bench.json")), symbolize_names: true)
runs = bench.is_a?(Hash) && bench[:runs] ? bench[:runs] : bench
expected_checksum = runs.values.flatten.map { _1[:checksum] }.uniq
expected_digest = runs.values.flatten.map { _1[:world_api_digest] }.compact.uniq
control = JSON.parse(File.read(File.join(ROOT, "docs/control.json")), symbolize_names: true)

checks = []
check = lambda do |id, desc, expected, actual|
  ok = expected == actual
  checks << { id: id, check: desc, expected: expected, actual: actual, ok: ok }
  $stderr.puts format("  [%s] %-8s %s", ok ? " ok " : "FAIL", id, desc)
end

worlds = Yarvpilled::World::KINDS.reject { _1 == :native }.select { Yarvpilled::World.available?(_1) }
$stderr.puts "yarvpilled #{Yarvpilled::VERSION} reproduce: worlds #{worlds.join(', ')}#{' (quick)' if quick}"

# C-BENCH-1: identical full-sim work (seed 11, 2000 ticks, events off) on every backend.
worlds.each do |w|
  sim = Yarvpilled::Simulation.new(seed: 11, world: w, events_enabled: false)
  2000.times { sim.step! }
  sum = [sim.births_total, sim.max_gen, sim.alive_count, sim.world.stats[:eaten], sim.species.size].join("-")
  sim.close
  check.("C-BENCH-1", "full-sim checksum, seed 11, 2000 ticks, world=#{w}", expected_checksum.first, sum)
end

# C-BENCH-2: the benchmark's world-API block lands on the recorded state digest on every backend.
worlds.each do |w|
  wd = Yarvpilled::Bench.fresh_world(w)
  sens = Array.new(520 * 6, 0)
  acts = Array.new(520) { |i| i % 4 }
  Yarvpilled::Bench::MICRO_TICKS.times { wd.sense(sens); wd.act(acts, 1 << 60) }
  check.("C-BENCH-2", "world-loop state digest after 600 ticks, world=#{w}", expected_digest.first, Yarvpilled::StateDigest.world(wd))
end

# C-CTRL-*: re-run recorded control replicates and compare every metric exactly.
rows = control[:rows]
pick = quick ? rows.first(2) : rows.select { [201, 202, 203].include?(_1[:seed]) }
metrics = %i[fitness survival species_entropy_bits opcode_entropy_bits mean_bytecode_len final_pop max_gen births]
pick.each do |r|
  got = Yarvpilled::Control.replicate(seed: r[:seed], control: r[:control].to_sym, ticks: r[:ticks],
                                      world: Yarvpilled::Native::AVAILABLE ? :native : :ruby)
  check.("C-CTRL-1", "control replicate seed #{r[:seed]} #{r[:control]}: all metrics", r.slice(*metrics), got.slice(*metrics).transform_values { _1.is_a?(Float) ? _1 : _1 })
end

# C-CTRL-2: the reported statistics recompute from the recorded rows.
stats = control[:stats]
recomputed = Yarvpilled::Control.permutation_p(stats[:fitness][:selection], stats[:fitness][:drift])
check.("C-CTRL-2", "fitness permutation p recomputed from docs/control.json", stats[:fitness][:p], recomputed)

sh = ->(*c) { IO.popen(c, err: File::NULL, &:read).lines.first&.strip rescue nil }
report = {
  replicator: who, date_utc: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"), yarvpilled: Yarvpilled::VERSION,
  git_commit: sh.("git", "-C", ROOT, "rev-parse", "--short=12", "HEAD"),
  platform: RUBY_PLATFORM, os: RbConfig::CONFIG["host_os"], cpu: RbConfig::CONFIG["host_cpu"], cpus: Etc.nprocessors,
  ruby: RUBY_DESCRIPTION, yjit: defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled? ? true : false,
  worlds: worlds, quick: quick, checks: checks, all_ok: checks.all? { _1[:ok] }
}
FileUtils.mkdir_p(File.dirname(out))
File.write(out, JSON.pretty_generate(report))
$stderr.puts "#{checks.count { _1[:ok] }}/#{checks.size} checks matched -> #{out}"
exit(report[:all_ok] ? 0 : 1)
