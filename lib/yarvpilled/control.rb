# frozen_string_literal: true

require "json"
require_relative "simulation"

module Yarvpilled
  # Selection vs. random-drift control experiment.
  #
  # For each seed we run two otherwise identical evolutions (events off, so
  # no Ractor blessings/TracePoint transfers):
  #   :selection  brain output drives behaviour; metabolic cost ~ bytecode length
  #   :drift      brain still runs, but actions are random and cost is flat:
  #               genomes carry no fitness signal (neutral null model)
  # Then every evolved population is measured in the same common-garden
  # assay: its most abundant genomes forage alone (brain-driven, flat cost,
  # fixed arena, no reproduction) and we record intake and survival.
  module Control
    ASSAY_TICKS = 300
    ASSAY_N = 40
    TOP_K = 8

    module_function

    # Brain-driven foraging in a fixed arena. Returns [intake/creature-tick, survival].
    def assay(genome, world_kind: Native::AVAILABLE ? :native : :ruby)
      w = World.build(world_kind, Simulation::WORLD_W, Simulation::WORLD_H, Simulation::FOOD_CELL, ASSAY_N)
      fw, fh, = w.food_dims
      w.fertility = (@fert ||= Simulation.fertility_bytes(0, fw, fh))
      w.fill_food(36)
      rng = Random.new(1234)
      ASSAY_N.times { w.spawn(rng.rand * Simulation::WORLD_W, rng.rand * Simulation::WORLD_H, rng.rand(64), 400, 0, 2) }
      brain = genome.brain
      sens = Array.new(ASSAY_N * 6, 0)
      acts = Array.new(ASSAY_N, 0)
      creature_ticks = 0
      ASSAY_TICKS.times do
        alive = w.sense(sens)
        creature_ticks += alive
        ASSAY_N.times do |i|
          b = i * 6
          acts[i] = brain.call(sens[b], sens[b + 1], sens[b + 2], sens[b + 3], sens[b + 4], sens[b + 5]) & 3
        end
        w.act(acts, 1 << 60)
      end
      st = w.stats
      [creature_ticks.zero? ? 0.0 : st[:eaten] * 1.5 / creature_ticks, st[:alive].to_f / ASSAY_N]
    end

    def entropy(counts)
      tot = counts.sum.to_f
      return 0.0 if tot.zero?

      -counts.sum { |c| c.zero? ? 0 : (c / tot) * Math.log2(c / tot) }
    end

    def replicate(seed:, control:, ticks:, world:)
      sim = Simulation.new(seed: seed, world: world, events_enabled: false, control: control)
      ticks.times { sim.step! }
      live = sim.live_species
      top = live.max_by(TOP_K, &:alive)
      scored = top.map { |sp| [sp.alive, *assay(sp.genome)] }
      wsum = scored.sum(&:first).to_f
      ops = Hash.new(0)
      live.each { |sp| sp.genome.histogram.each { |k, v| ops[k] += v * sp.alive } }
      {
        seed: seed, control: control, ticks: ticks,
        fitness: wsum.zero? ? 0.0 : scored.sum { |n, f, _| n * f } / wsum,
        survival: wsum.zero? ? 0.0 : scored.sum { |n, _, s| n * s } / wsum,
        final_pop: sim.alive_count,
        species_entropy_bits: entropy(live.map(&:alive)),
        opcode_entropy_bits: entropy(ops.values),
        mean_bytecode_len: live.sum { |s| s.genome.bytecode_len * s.alive } / [sim.alive_count, 1].max.to_f,
        max_gen: sim.max_gen, births: sim.births_total, resurrections: sim.resurrections
      }
    end

    EXACT_LIMIT = 200_000 # relabelings; above this use a seeded Monte Carlo permutation test
    MC_PERMUTATIONS = 100_000
    BOOTSTRAP = 10_000

    # Two-sided permutation test on the difference of means. Exact (all
    # relabelings) when feasible, otherwise Monte Carlo with a fixed seed and
    # the (1 + extreme) / (1 + B) estimator, which is never anti-conservative.
    def permutation_p(a, b, mc: MC_PERMUTATIONS, seed: 7)
      n_rel = binom(a.size + b.size, a.size)
      return permutation_p_exact(a, b) if n_rel <= EXACT_LIMIT

      rng = Random.new(seed)
      all = a + b
      obs = (mean(a) - mean(b)).abs
      extreme = 0
      mc.times do
        sh = all.shuffle(random: rng)
        extreme += 1 if (mean(sh.first(a.size)) - mean(sh.drop(a.size))).abs >= obs - 1e-12
      end
      (1 + extreme).to_f / (1 + mc)
    end

    def binom(n, k) = (1..k).reduce(1) { |acc, i| acc * (n - k + i) / i }

    # Percentile bootstrap 95% CIs (resampling within each arm, fixed seed) for
    # the difference of means and for Cohen's d.
    def bootstrap_ci(a, b, reps: BOOTSTRAP, seed: 42)
      rng = Random.new(seed)
      diffs = []
      ds = []
      reps.times do
        ra = Array.new(a.size) { a[rng.rand(a.size)] }
        rb = Array.new(b.size) { b[rng.rand(b.size)] }
        diffs << mean(ra) - mean(rb)
        ds << cohens_d(ra, rb)
      end
      q = ->(v, p) { s = v.sort; s[((s.size - 1) * p).round] }
      { diff: [q.(diffs, 0.025), q.(diffs, 0.975)], d: [q.(ds, 0.025), q.(ds, 0.975)], reps: reps, seed: seed }
    end

    def permutation_p_exact(a, b)
      all = a + b
      n = a.size
      obs = (mean(a) - mean(b)).abs
      total = 0
      extreme = 0
      all.each_index.to_a.combination(n) do |idx|
        set = idx.to_h { [_1, true] }
        ga = []
        gb = []
        all.each_with_index { |v, i| (set[i] ? ga : gb) << v }
        total += 1
        extreme += 1 if (mean(ga) - mean(gb)).abs >= obs - 1e-12
      end
      extreme.to_f / total
    end

    def mean(a) = a.sum.to_f / a.size

    def sd(a)
      m = mean(a)
      Math.sqrt(a.sum { (_1 - m)**2 } / (a.size - 1))
    end

    def cohens_d(a, b)
      sp = Math.sqrt(((a.size - 1) * sd(a)**2 + (b.size - 1) * sd(b)**2) / (a.size + b.size - 2))
      sp.zero? ? 0.0 : (mean(a) - mean(b)) / sp
    end

    METRICS = {
      fitness: "assay fitness (energy intake / creature-tick)",
      survival: "assay survival (fraction alive after 300 ticks)",
      species_entropy_bits: "species entropy (bits)",
      opcode_entropy_bits: "opcode entropy (bits)",
      mean_bytecode_len: "mean bytecode length (words)",
      final_pop: "final population (in-sim, context only)"
    }.freeze

    # Replicates are independent and deterministic, so they can run in forked
    # workers (where fork exists) without changing any result.
    def run(replicates:, ticks:, out_dir:, world: Native::AVAILABLE ? :native : :ruby, first_seed: 101, workers: 1)
      seeds = (first_seed...(first_seed + replicates)).to_a
      jobs = seeds.flat_map { |s| %i[selection drift].map { |c| [s, c] } }
      rows = parallel_map(jobs, workers) do |s, c|
        $stderr.puts "  seed #{s} #{c} ..."
        replicate(seed: s, control: c, ticks: ticks, world: world)
      end
      report(rows, replicates: replicates, ticks: ticks, out_dir: out_dir, world: world, first_seed: first_seed)
    end

    def parallel_map(jobs, workers, &blk)
      return jobs.map(&blk) if workers <= 1 || !Process.respond_to?(:fork)

      jobs.each_slice((jobs.size.to_f / workers).ceil).map do |chunk|
        rd, wr = IO.pipe
        pid = fork do
          rd.close
          wr.write(Marshal.dump(chunk.map(&blk)))
          wr.close
          exit!(0)
        end
        wr.close
        [pid, rd]
      end.flat_map do |pid, rd|
        data = rd.read
        rd.close
        Process.wait(pid)
        raise "control worker #{pid} failed" unless $?.success?

        Marshal.load(data)
      end
    end

    # Holm-Bonferroni step-down adjustment across the metrics tested.
    def perm_desc(n)
      rel = binom(2 * n, n)
      rel <= EXACT_LIMIT ? "exact, all C(#{2 * n},#{n}) = #{rel} relabelings" : "Monte Carlo, #{MC_PERMUTATIONS} seeded relabelings of C(#{2 * n},#{n}) = #{rel}"
    end

    def min_p(n)
      rel = binom(2 * n, n)
      rel <= EXACT_LIMIT ? 2.0 / rel : 1.0 / (1 + MC_PERMUTATIONS)
    end

    def holm(ps)
      order = ps.each_with_index.sort_by(&:first)
      adj = Array.new(ps.size)
      running = 0.0
      order.each_with_index do |(p, i), rank|
        running = [running, [(ps.size - rank) * p, 1.0].min].max
        adj[i] = running
      end
      adj
    end

    def report(rows, replicates:, ticks:, out_dir:, world:, first_seed: 101)
      rows = rows.map { |r| r.transform_keys(&:to_sym).merge(control: r[:control].to_sym) }
      seed_fit, seed_surv = assay(Genome.seed)
      md = +"# Selection vs. random drift (control experiment)\n\n"
      md << "#{replicates} seeds x 2 conditions, #{ticks} ticks each, events off, world=#{world}. " \
            "Selection: brain output drives behaviour, cost scales with bytecode. Drift (null model): brain still runs, " \
            "actions are random, cost is flat, so genomes carry no fitness signal. " \
            "Common-garden assay: top #{TOP_K} species per population (abundance-weighted), #{ASSAY_N} clones each, " \
            "#{ASSAY_TICKS} ticks, flat cost, no reproduction. Seeds #{first_seed}..#{first_seed + replicates - 1}. " \
            "Test: two-sided permutation test on the difference of means (#{perm_desc(replicates)}), " \
            "with Holm-Bonferroni correction across the #{METRICS.size} metrics; 95% percentile bootstrap CIs " \
            "(#{BOOTSTRAP} resamples within arm, seed 42) for the difference and for Cohen's d. The hand-written seed genome scores " \
            "fitness #{seed_fit.round(3)} and survival #{seed_surv.round(3)} in the same assay.\n\n"
      md << "| metric | selection mean +/- sd | drift mean +/- sd | diff [95% CI] | Cohen's d [95% CI] | permutation p | Holm-adjusted p |\n|---|---:|---:|---:|---:|---:|---:|\n"
      stats = METRICS.to_h do |k, _|
        a = rows.select { _1[:control] == :selection }.map { _1[k].to_f }
        b = rows.select { _1[:control] == :drift }.map { _1[k].to_f }
        [k, { selection: a, drift: b, p: permutation_p(a, b), d: cohens_d(a, b), ci: bootstrap_ci(a, b) }]
      end
      adj = holm(stats.values.map { _1[:p] })
      stats.each_with_index do |(k, st), i|
        st[:p_holm] = adj[i]
        a = st[:selection]
        b = st[:drift]
        ci = st[:ci]
        md << format("| %s | %.3f +/- %.3f | %.3f +/- %.3f | %+.3f [%+.3f, %+.3f] | %.2f [%.2f, %.2f] | %.4f | %.4f |\n", METRICS[k],
                     mean(a), sd(a), mean(b), sd(b), mean(a) - mean(b), ci[:diff][0], ci[:diff][1], st[:d], ci[:d][0], ci[:d][1],
                     st[:p], adj[i])
      end
      md << "\nPer-replicate rows are in control.json.\n"
      md << "\nThe minimum attainable p is #{format('%.2g', min_p(replicates))}.\n"
      File.write(File.join(out_dir, "control.md"), md)
      File.write(File.join(out_dir, "control.json"), JSON.pretty_generate(rows: rows, stats: stats, seed_genome: { fitness: seed_fit, survival: seed_surv }))
      md
    end
  end
end
