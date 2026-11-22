# frozen_string_literal: true

require "json"
require "rbconfig"
require "etc"

module Yarvpilled
  # Honest multi-tier benchmark.
  #
  # Every tier is a separate `ruby` process (YJIT can't be switched off once
  # on), repeated N times; we report the median and the min-max spread.
  #
  # Three measurements per run:
  #   full sim     evolution core with events off (no Ractors, compaction,
  #                TracePoint, dreams). With a fixed seed every tier performs
  #                the identical evolution, and the checksum proves it.
  #                creatures/sec = think() calls (creature-updates) per second.
  #   world API    world loop only through the Ruby API (sense+act incl. the
  #                Array<->buffer glue), 400 bodies, fixed actions, no brains.
  #   kernel       native kernels alone, no Ruby glue (C/asm/Rust only), plus
  #                the isolated crowd-sensing scan (the asm target).
  module Bench
    TIERS = [
      ["pure Ruby interpreter", [], "ruby"],
      ["pure Ruby + YJIT", ["--yjit"], "ruby"],
      ["C + YJIT", ["--yjit"], "c"],
      ["Rust + YJIT", ["--yjit"], "rust"],
      ["asm + YJIT", ["--yjit"], "asm"],
      ["C, interpreter (extra)", [], "c"]
    ].freeze
    MICRO_TICKS = 600 # < MAX_AGE (900), so no body dies of old age mid-measure
    MICRO_BODIES = 400

    module_function

    def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    # Runs inside a tier process; returns one Hash.
    def run_tier(world:, ticks:, seed:)
      require_relative "simulation"
      world = world.to_sym
      sim = Simulation.new(seed: seed, world: world, events_enabled: false)
      GC.start
      gc0 = GC.stat
      t0 = now
      ticks.times { sim.step! }
      dt = now - t0
      gc1 = GC.stat
      prof = sim.prof
      ptot = prof.values.sum
      sum = [sim.births_total, sim.max_gen, sim.alive_count, sim.world.stats[:eaten], sim.species.size]
      res = {
        world: world, yjit: defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled? ? true : false, ticks: ticks,
        seconds: dt, creatures_per_sec: sim.think_calls / dt, generations_per_sec: sim.max_gen / dt,
        ticks_per_sec: ticks / dt, checksum: sum.join("-"),
        share: prof.transform_values { _1 / ptot },
        allocated_objects: gc1[:total_allocated_objects] - gc0[:total_allocated_objects], gc_runs: gc1[:count] - gc0[:count]
      }
      sim.close
      res.merge(world_api(world)).merge(kernel(world))
    end

    def fresh_world(world)
      w = World.build(world, 768, 512, 8, 520)
      w.fertility = Array.new(96 * 64) { |i| (i * 37) % 120 }.pack("C*")
      w.fill_food(60)
      r = Random.new(3)
      MICRO_BODIES.times { w.spawn(r.rand * 768, r.rand * 512, r.rand(64), 1_000_000_000, 0, 1) }
      w
    end

    def world_api(world)
      updates = 0
      spent = 0.0
      while spent < 1.0
        w = fresh_world(world)
        sens = Array.new(520 * 6, 0)
        acts = Array.new(520) { |i| i % 4 }
        t0 = now
        MICRO_TICKS.times do
          updates += w.sense(sens)
          w.act(acts, 1 << 60)
        end
        spent += now - t0
      end
      { world_api_updates_per_sec: updates / spent }
    end

    def kernel(world)
      w0 = fresh_world(world)
      return { kernel_updates_per_sec: nil, crowd_ns: nil } unless w0.respond_to?(:kernel_bench)

      ts = ta = tc = 0.0
      updates = 0
      crowd_ok = true
      while ts + ta < 1.0
        s, a, c, u = fresh_world(world).kernel_bench(MICRO_TICKS)
        ts += s
        ta += a
        c ? tc += c : crowd_ok = false
        updates += u
      end
      { kernel_updates_per_sec: updates / (ts + ta), kernel_sense_share: ts / (ts + ta),
        crowd_ns: crowd_ok ? tc / updates * 1e9 : nil }
    end

    def stats(vals)
      v = vals.compact.sort
      return nil if v.empty?

      med = v.size.odd? ? v[v.size / 2] : (v[v.size / 2 - 1] + v[v.size / 2]) / 2.0
      { median: med, min: v.first, max: v.last, spread_pct: med.zero? ? 0 : (v.last - v.first) / med * 100 }
    end

    def fmt(st, digits = 0)
      return "n/a" unless st

      f = ->(x) { digits.zero? ? x.round.to_s.reverse.scan(/\d{1,3}/).join(",").reverse : format("%.#{digits}f", x) }
      "#{f.call(st[:median])} (#{f.call(st[:min])}-#{f.call(st[:max])})"
    end

    def run_all(ticks:, seed:, out_dir:, repeats: 5)
      root = File.expand_path("../..", __dir__)
      yjit = system(RbConfig.ruby, "--yjit", "-e", "exit(defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled? ? 0 : 1)",
                    err: File::NULL)
      tiers = TIERS.select { |_, flags, w| World.available?(w.to_sym) && (yjit || !flags.include?("--yjit")) }
      runs = tiers.to_h do |label, flags, world|
        res = Array.new(repeats) do |k|
          $stderr.puts "  #{label}: run #{k + 1}/#{repeats}"
          cmd = [RbConfig.ruby, *flags, File.join(root, "yarv_brain.rb"), "--bench-tier", "--world=#{world}", "--ticks=#{ticks}", "--seed=#{seed}"]
          JSON.parse(IO.popen(cmd, &:read).lines.last, symbolize_names: true)
        end
        [label, res]
      end
      report(runs, ticks: ticks, seed: seed, out_dir: out_dir, repeats: repeats)
    end

    def report(runs, ticks:, seed:, out_dir:, repeats:)
      base = stats(runs.values.first.map { _1[:creatures_per_sec] })[:median]
      base_api = stats(runs.values.first.map { _1[:world_api_updates_per_sec] })[:median]
      cpu = File.read("/proc/cpuinfo")[/model name\s*:\s*(.*)/, 1] rescue RUBY_PLATFORM
      md = +"# YARVPILLED benchmark\n\n"
      md << "ruby #{RUBY_VERSION} | #{cpu} | #{Etc.nprocessors} cpus | seed #{seed} | #{ticks} ticks | " \
            "#{repeats} runs per tier, each a fresh process | values are **median (min-max)**\n\n"
      md << "## Full simulation (brains + world)\n\n"
      md << "| tier | creatures/sec | generations/sec | ticks/sec | vs pure Ruby | time in brains (YARV think) | time compiling births (mutate+ISeq) | time in world (sense+act) | spread | checksum |\n"
      md << "|---|---:|---:|---:|---:|---:|---:|---:|---:|---|\n"
      runs.each do |label, rs|
        c = stats(rs.map { _1[:creatures_per_sec] })
        brains = stats(rs.map { _1[:share][:brains] })
        worldsh = stats(rs.map { _1[:share][:sense] + _1[:share][:act] })
        birth = stats(rs.map { _1[:share][:births] })
        md << "| #{label} | #{fmt(c)} | #{fmt(stats(rs.map { _1[:generations_per_sec] }), 2)} | #{fmt(stats(rs.map { _1[:ticks_per_sec] }))} | " \
              "#{format('%.2fx', c[:median] / base)} | #{format('%.0f%%', brains[:median] * 100)} | #{format('%.0f%%', birth[:median] * 100)} | #{format('%.0f%%', worldsh[:median] * 100)} | " \
              "#{format('%.1f%%', c[:spread_pct])} | `#{rs.map { _1[:checksum] }.uniq.join(', ')}` |\n"
      end
      md << "\n## World loop only (no brains)\n\n"
      md << "| tier | world via Ruby API (updates/sec) | vs pure Ruby | kernel only, no Ruby glue (updates/sec) | crowd scan (ns/creature) | spread (API) |\n"
      md << "|---|---:|---:|---:|---:|---:|\n"
      runs.each do |label, rs|
        api = stats(rs.map { _1[:world_api_updates_per_sec] })
        md << "| #{label} | #{fmt(api)} | #{format('%.1fx', api[:median] / base_api)} | #{fmt(stats(rs.map { _1[:kernel_updates_per_sec] }))} | " \
              "#{fmt(stats(rs.map { _1[:crowd_ns] }), 1)} | #{format('%.1f%%', api[:spread_pct])} |\n"
      end
      sums = runs.values.flatten.map { _1[:checksum] }.uniq
      md << "\nIdentical full-sim checksum across all #{runs.values.flatten.size} runs: **#{sums.size == 1}** (`#{sums.join(', ')}`; " \
            "births-maxgen-alive-food_eaten-species). The world backends are also bit-identical step by step " \
            "(test/test_world_equivalence.rb).\n"
      File.write(File.join(out_dir, "bench.md"), md)
      File.write(File.join(out_dir, "bench.json"), JSON.pretty_generate(runs))
      md
    end
  end
end
