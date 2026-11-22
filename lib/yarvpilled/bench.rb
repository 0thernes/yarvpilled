# frozen_string_literal: true

require "json"
require "rbconfig"

module Yarvpilled
  # Honest three-tier benchmark.
  #
  # Each tier is a separate `ruby` process (YJIT can't be toggled off once
  # on). The evolution core runs with events disabled (no Ractors, no GC
  # compaction, no TracePoint, no ObjectSpace dreams), so with a fixed seed
  # every tier performs the *identical* evolutionary trajectory: the same
  # births, the same genomes, the same think() calls. A checksum proves it.
  module Bench
    TIERS = [
      ["pure Ruby interpreter", [], "ruby"],
      ["pure Ruby + YJIT", ["--yjit"], "ruby"],
      ["C ext, interpreter (extra)", [], "native"],
      ["C ext + YJIT", ["--yjit"], "native"]
    ].freeze

    module_function

    # Runs inside a tier process; prints one JSON line.
    def run_tier(world:, ticks:, seed:)
      require_relative "simulation"
      sim = Simulation.new(seed: seed, world: world, events_enabled: false)
      GC.start
      gc0 = GC.stat
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      ticks.times { sim.step! }
      dt = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
      gc1 = GC.stat
      micro = world_micro(world)
      sum = [sim.births_total, sim.max_gen, sim.alive_count, sim.world.stats[:eaten], sim.species.size]
      {
        world: world, yjit: defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled? ? true : false, ticks: ticks, seconds: dt.round(3),
        think_calls: sim.think_calls, creatures_per_sec: (sim.think_calls / dt).round,
        generations: sim.max_gen, generations_per_sec: (sim.max_gen / dt).round(2), births: sim.births_total,
        ticks_per_sec: (ticks / dt).round(1), checksum: sum.join("-"),
        allocated_objects: gc1[:total_allocated_objects] - gc0[:total_allocated_objects],
        gc_runs: gc1[:count] - gc0[:count], world_micro_updates_per_sec: micro
      }
    ensure
      sim&.close
    end

    # World-loop-only microbenchmark: 400 bodies, fixed pseudo-random
    # actions, no genomes. Isolates C vs Ruby for the hot loop itself.
    def world_micro(world)
      require_relative "world"
      w = World.build(world, 768, 512, 8, 520)
      w.fertility = Array.new(96 * 64) { |i| (i * 37) % 120 }.pack("C*")
      w.fill_food(60)
      r = Random.new(3)
      400.times { w.spawn(r.rand * 768, r.rand * 512, r.rand(64), 100_000, 0, 1) }
      sens = Array.new(520 * 6, 0)
      acts = Array.new(520) { |i| i % 4 }
      n = 0
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      while Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0 < 1.5
        w.sense(sens)
        w.act(acts, 10_000_000)
        n += 400
      end
      (n / (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0)).round
    end

    def run_all(ticks:, seed:, out_dir:)
      root = File.expand_path("../..", __dir__)
      rows = TIERS.map do |label, flags, world|
        cmd = [RbConfig.ruby, *flags, File.join(root, "yarv_brain.rb"), "--bench-tier", "--world=#{world}", "--ticks=#{ticks}", "--seed=#{seed}"]
        $stderr.puts "  running: #{label} ..."
        res = JSON.parse(IO.popen(cmd, &:read).lines.last, symbolize_names: true)
        [label, res]
      end
      base = rows.first[1][:creatures_per_sec].to_f
      md = +"# YARVPILLED benchmark\n\n"
      md << "ruby #{RUBY_VERSION} | #{RUBY_PLATFORM} | #{ticks} ticks | seed #{seed} | #{Etc.respond_to?(:nprocessors) ? Etc.nprocessors : '?'} cpus\n\n"
      md << "| tier | creatures/sec (think calls) | generations/sec | ticks/sec | speedup | world-loop micro (updates/sec) | allocations | GC runs | checksum |\n"
      md << "|---|---:|---:|---:|---:|---:|---:|---:|---|\n"
      rows.each do |label, r|
        md << "| #{label} | #{r[:creatures_per_sec]} | #{r[:generations_per_sec]} | #{r[:ticks_per_sec]} | #{(r[:creatures_per_sec] / base).round(2)}x | #{r[:world_micro_updates_per_sec]} | #{r[:allocated_objects]} | #{r[:gc_runs]} | `#{r[:checksum]}` |\n"
      end
      same = rows.map { _2[:checksum] }.uniq.size == 1
      md << "\nIdentical checksum across tiers: **#{same}** (births-maxgen-alive-food_eaten-species), i.e. every tier did exactly the same evolutionary work.\n"
      File.write(File.join(out_dir, "bench.md"), md)
      File.write(File.join(out_dir, "bench.json"), JSON.pretty_generate(rows.to_h))
      md
    end
  end
end
