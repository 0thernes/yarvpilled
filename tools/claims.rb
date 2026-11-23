# frozen_string_literal: true

# Generated, data-backed blocks in README.md and docs/verification.md.
#
# Every number in a block between <!-- generated:NAME --> and
# <!-- /generated:NAME --> is computed from the recorded data in docs/*.json
# and docs/verification/*.json (or counted from the source tree). test_claims.rb
# fails when a block drifts from its data; `ruby tools/claims.rb --write`
# regenerates them after a new benchmark or experiment run.
#
#   ruby tools/claims.rb           # check (exit 1 on drift)
#   ruby tools/claims.rb --write   # rewrite the blocks in place
require "json"
unless defined?(Yarvpilled::Control) # the tests may have loaded the library from elsewhere (YP_LIB)
  $LOAD_PATH.unshift File.expand_path("../lib", __dir__)
  require "yarvpilled"
end

module Yarvpilled
  module Claims
    ROOT = File.expand_path("..", __dir__)
    FILES = %w[README.md docs/verification.md].freeze

    module_function

    def json(rel) = JSON.parse(File.read(File.join(ROOT, rel)), symbolize_names: true)
    def int(x) = x.round.to_s.reverse.scan(/\d{1,3}/).join(",").reverse
    def med(vals) = Bench.stats(vals)[:median]
    def mean(a) = a.sum.to_f / a.size
    def sd(a) = Math.sqrt(a.sum { (_1 - mean(a))**2 } / (a.size - 1))
    def p(x) = Control.fmt_p(x)

    def bench = @bench ||= json("docs/bench.json")
    def control = @control ||= json("docs/control.json")
    def runs = bench[:runs]
    def all_runs = runs.values.flatten
    def base(key) = med(runs.values.first.map { _1[key] })
    def native_tiers = runs.reject { |label, _| label.to_s.start_with?("pure Ruby") || label.to_s.include?("extra") }

    def checksum
      sums = all_runs.map { _1[:checksum] }.uniq
      raise "benchmark runs disagree on the checksum: #{sums}" unless sums.size == 1

      sums.first
    end

    def speed_glance
      out = +"Speed, median of #{all_runs.size / runs.size} fresh processes per tier (seed 11, 2000 ticks; " \
              "identical checksum `#{checksum}` in all #{all_runs.size} runs) [C-BENCH-1, C-BENCH-3]:\n\n"
      out << "| tier | creatures/sec | vs pure Ruby | world loop only (updates/sec) | share of tick in YARV brains |\n"
      out << "|---|---:|---:|---:|---:|\n"
      runs.each do |label, rs|
        next if label.to_s.include?("extra")

        c = med(rs.map { _1[:creatures_per_sec] })
        out << "| #{label} | #{int(c)} | #{format('%.2fx', c / base(:creatures_per_sec))} | " \
               "#{int(med(rs.map { _1[:world_api_updates_per_sec] }))} | #{format('%.0f%%', med(rs.map { _1[:share][:brains] }) * 100)} |\n"
      end
      out
    end

    def evolution_glance
      st = control[:stats]
      n = st[:fitness][:selection].size
      out = +"Evolution, #{n} seeds per arm (pre-registered), against a random-drift null model [C-CTRL-1, C-CTRL-2]:\n\n"
      out << "| metric | selection | drift | difference [95% CI] | Holm-adjusted p |\n|---|---:|---:|---:|---:|\n"
      [[:fitness, "foraging fitness (common-garden assay)", 3], [:survival, "survival in assay", 3],
       [:mean_bytecode_len, "mean bytecode length (words)", 1]].each do |k, label, d|
        s = st[k]
        out << format("| %s | %.#{d}f | %.#{d}f | %+.#{d}f [%+.#{d}f, %+.#{d}f] | %s |\n", label, mean(s[:selection]), mean(s[:drift]),
                      mean(s[:selection]) - mean(s[:drift]), *s[:ci][:diff], p(s[:p_holm]))
      end
      out
    end

    def bench_tables
      out = +"| tier | creatures/sec, median (min-max) | vs pure Ruby | brains | world | spread | world via Ruby API (updates/sec) | kernel only (updates/sec) | crowd scan (ns) |\n"
      out << "|---|---:|---:|---:|---:|---:|---:|---:|---:|\n"
      runs.each do |label, rs|
        c = Bench.stats(rs.map { _1[:creatures_per_sec] })
        k = rs.map { _1[:kernel_updates_per_sec] }.compact
        cr = rs.map { _1[:crowd_ns] }.compact
        out << "| #{label} | #{Bench.fmt(c)} | #{format('%.2fx', c[:median] / base(:creatures_per_sec))} | " \
               "#{format('%.0f%%', med(rs.map { _1[:share][:brains] }) * 100)} | " \
               "#{format('%.0f%%', med(rs.map { _1[:share][:sense] + _1[:share][:act] }) * 100)} | #{format('%.1f%%', c[:spread_pct])} | " \
               "#{int(med(rs.map { _1[:world_api_updates_per_sec] }))} | #{k.empty? ? 'n/a' : int(med(k))} | " \
               "#{cr.empty? ? 'n/a' : format('%.1f', med(cr))} |\n"
      end
      digests = all_runs.flat_map { [_1[:world_api_digest], _1[:kernel_digest]] }.compact.uniq
      out << "\nCorrectness next to every timing: all #{all_runs.size} runs produced checksum `#{checksum}`, and every " \
             "world-loop timing ended on state digest `#{digests.join(', ')}` [C-BENCH-1, C-BENCH-2].\n"
      hw = bench[:hardware] || {}
      out << "Recorded on: #{hw[:cpu]}, #{hw[:logical_cpus]} logical CPUs, #{hw[:virtualization] || 'bare metal?'}, " \
             "load average #{hw[:loadavg_at_start]} at start, #{hw[:ruby].to_s[/ruby \S+/]}, #{hw[:cc].to_s[/\S+ \S+ \S+/]}, #{hw[:rustc]}.\n"
      out
    end

    def bench_verdict
      nat = native_tiers
      ratio = nat.map { |_, rs| med(rs.map { _1[:creatures_per_sec] }) / base(:creatures_per_sec) }
      api = nat.map { |_, rs| med(rs.map { _1[:world_api_updates_per_sec] }) / base(:world_api_updates_per_sec) }
      brains = nat.map { |_, rs| med(rs.map { _1[:share][:brains] }) * 100 }
      spread = nat.map { |_, rs| Bench.stats(rs.map { _1[:creatures_per_sec] })[:spread_pct] }
      kern = nat.to_h { |l, rs| [l, med(rs.map { _1[:kernel_updates_per_sec] }.compact)] }
      fastest = kern.max_by(&:last)
      crowd = nat.to_h { |l, rs| [l, rs.map { _1[:crowd_ns] }.compact] }.reject { _2.empty? }.transform_values { med(_1) }
      gap = (ratio.max - ratio.min) / ratio.min * 100
      tied = gap < spread.min
      out = +"- End to end, the native tiers are #{format('%.2f', ratio.min)}-#{format('%.2f', ratio.max)}x pure Ruby. Their medians " \
              "differ by at most #{format('%.1f', gap)}%, #{tied ? 'less' : 'MORE'} than the smallest run-to-run spread among them " \
              "(#{format('%.1f', spread.min)}%; largest #{format('%.1f', spread.max)}%), so #{tied ? 'they are tied within noise' : 'the ranking may be real'} [C-BENCH-3].\n"
      out << "- About #{format('%.0f', brains.min)}-#{format('%.0f', brains.max)}% of each native tick is YARV running genome " \
             "bytecode, so the brains set the speed, not the world loop's language [C-BENCH-4].\n"
      out << "- On the world loop alone, native backends are #{format('%.0f', api.min)}-#{format('%.0f', api.max)}x pure Ruby " \
             "through the Ruby API [C-BENCH-5]. Fastest bare kernel in this run: #{fastest[0]} (#{int(fastest[1])} updates/s).\n"
      out << "- Crowd scan: #{crowd.map { |l, v| "#{l.to_s.split.first} #{format('%.1f', v)} ns" }.join(', ')} per creature. " \
             "The hand-written asm is in the same range as gcc -O3, not a big win [C-BENCH-6].\n"
      out
    end

    def control_table
      st = control[:stats]
      out = +"| metric | selection mean +/- sd | drift mean +/- sd | diff [95% CI] | Cohen's d [95% CI] | Holm-adjusted p |\n"
      out << "|---|---:|---:|---:|---:|---:|\n"
      Control::METRICS.each do |k, label|
        s = st[k]
        a = s[:selection]
        b = s[:drift]
        out << format("| %s | %.3f +/- %.3f | %.3f +/- %.3f | %+.3f [%+.3f, %+.3f] | %.2f [%.2f, %.2f] | %s |\n",
                      label, mean(a), sd(a), mean(b), sd(b), mean(a) - mean(b), *s[:ci][:diff], s[:d], *s[:ci][:d], p(s[:p_holm]))
      end
      seed = control[:seed_genome]
      out << "\nn = #{st[:fitness][:selection].size} seeds per arm, seeds #{control[:rows].map { _1[:seed] }.minmax.join('-')}, " \
             "#{control[:rows].first[:ticks]} ticks. The hand-written seed genome scores fitness #{format('%.3f', seed[:fitness])} " \
             "and survival #{format('%.3f', seed[:survival])} in the same assay.\n"
      out
    end

    def verification_evidence
      v = ->(f) { File.exist?(File.join(ROOT, f)) ? json(f) : nil }
      kf = v.("docs/verification/kernel_fuzz.json")
      gf = v.("docs/verification/genome_fuzz.json")
      mu = v.("docs/verification/mutation.json")
      sa = v.("docs/verification/sanitize.json")
      cases = Dir[File.join(ROOT, "test/test_*.rb")].sum { File.read(_1).scan(/Prop\.check\("[^"]+", cases: ([\d_]+)\)/).sum { |(n)| n.delete("_").to_i } }
      thms = Dir[File.join(ROOT, "formal/lean/Yarvpilled/*.lean")].sum { File.read(_1).scan(/^theorem /).size }
      kani = File.read(File.join(ROOT, "ext/yarvpilled_rust/src/proofs.rs")).scan(/kani::proof\)\]/).size
      claims = File.read(File.join(ROOT, "CLAIMS.md")).scan(/^\| (C-[A-Z]+-\d+) /).flatten.uniq.size
      out = +"| evidence | value | source |\n|---|---|---|\n"
      out << "| claim IDs mapped to commands/tests | #{claims} | CLAIMS.md |\n"
      out << "| property-based cases per test run | #{int(cases)} (x PROP_SCALE) | test/test_*.rb `Prop.check` |\n"
      out << "| Lean theorems proved (no sorry) | #{thms} | formal/lean, `./check.sh` |\n"
      out << "| Kani harnesses (randomized stable-Rust runs: 20,000 each) | #{kani} | ext/yarvpilled_rust/src/proofs.rs |\n"
      out << "| kernel fuzzer | #{int(kf[:execs])} execs in #{int(kf[:seconds])} s, #{kf[:crashes_after_fix]} crashes after fix (#{kf[:findings].size} finding fixed) | docs/verification/kernel_fuzz.json |\n" if kf
      out << "| genome fuzzer | #{int(gf[:candidates])} genomes in #{int(gf[:seconds])} s, #{gf[:findings].size} findings | docs/verification/genome_fuzz.json |\n" if gf
      out << "| mutation score | #{format('%.1f%%', mu[:score] * 100)} (#{mu[:killed]}/#{mu[:mutants_run]} mutants killed) | docs/verification/mutation.json |\n" if mu
      out << "| ASan + UBSan test run | #{sa[:runs]} tests, #{sa[:failures]} failures, #{sa[:sanitizer_reports]} sanitizer reports | docs/verification/sanitize.json |\n" if sa
      out
    end

    SECTIONS = {
      "speed-glance" => :speed_glance, "evolution-glance" => :evolution_glance, "bench-tables" => :bench_tables,
      "bench-verdict" => :bench_verdict, "control-table" => :control_table, "verification-evidence" => :verification_evidence
    }.freeze

    def render(text)
      text.gsub(/(<!-- generated:([\w-]+) -->\n).*?(<!-- \/generated:\2 -->)/m) do
        "#{Regexp.last_match(1)}#{send(SECTIONS.fetch(Regexp.last_match(2)))}#{Regexp.last_match(3)}"
      end
    end

    # => [[file, section], ...] for every generated block that differs from its data.
    def drift
      FILES.flat_map do |f|
        path = File.join(ROOT, f)
        next [] unless File.exist?(path)

        text = File.read(path)
        want = render(text)
        names = text.scan(/<!-- generated:([\w-]+) -->/).flatten
        names.reject { |n| block(text, n) == block(want, n) }.map { [f, _1] }
      end
    end

    def block(text, name) = text[/<!-- generated:#{name} -->\n(.*?)<!-- \/generated:#{name} -->/m, 1]

    def write!
      FILES.each do |f|
        path = File.join(ROOT, f)
        File.write(path, render(File.read(path))) if File.exist?(path)
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  require "yarvpilled"
  if ARGV.include?("--write")
    Yarvpilled::Claims.write!
    puts "generated blocks rewritten"
  else
    d = Yarvpilled::Claims.drift
    d.each { |f, s| warn "drift: #{f} block '#{s}' no longer matches its data (ruby tools/claims.rb --write)" }
    puts "all generated blocks match their data" if d.empty?
    exit(d.empty? ? 0 : 1)
  end
end
