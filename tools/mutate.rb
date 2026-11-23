# frozen_string_literal: true

# Homegrown mutation testing (layer 6). For each target method, every simple
# source mutation (operator swap, comparison flip, literal +-1, boolean flip,
# min/max swap) is applied ONE AT A TIME to a copy of lib/, and the target's
# test files are run against the copy (YP_LIB). A mutant is "killed" if any
# test fails or the run times out; otherwise it "survived" and is listed, with
# its line, so a human can judge whether it is equivalent or a real test gap.
#
#   ruby tools/mutate.rb [--max=N per target] [--jobs=N] [--out=docs/verification/mutation.json] [--only=world_ruby]
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "json"
require "time"
require "fileutils"
require "open3"
require "etc"
require "rbconfig"

ROOT = File.expand_path("..", __dir__)
RUBY = RbConfig.ruby
opts = { max: 120, jobs: [Etc.nprocessors - 1, 1].max, out: File.join(ROOT, "docs/verification/mutation.json"), only: nil, timeout: 120 }
ARGV.each do |a|
  case a
  when /\A--max=(\d+)\z/ then opts[:max] = Integer(Regexp.last_match(1))
  when /\A--jobs=(\d+)\z/ then opts[:jobs] = Integer(Regexp.last_match(1))
  when /\A--out=(.+)\z/ then opts[:out] = File.expand_path(Regexp.last_match(1))
  when /\A--only=(.+)\z/ then opts[:only] = Regexp.last_match(1)
  when /\A--timeout=(\d+)\z/ then opts[:timeout] = Integer(Regexp.last_match(1))
  else abort "usage: ruby tools/mutate.rb [--max=N] [--jobs=N] [--out=FILE] [--only=NAME] [--timeout=SECS]"
  end
end

# name => [file, methods to mutate (whole method bodies), tests that guard them]
TARGETS = {
  "world_ruby" => ["lib/yarvpilled/world_ruby.rb", %w[initialize sense act spawn split feed food_index wrapd tdelta build_grid],
                   %w[test/test_differential.rb test/test_properties.rb test/test_negative.rb test/test_world_equivalence.rb test/test_edges.rb]],
  "genome_grammar" => ["lib/yarvpilled/genome.rb", %w[validate! check_expr check_cond expr render],
                       %w[test/test_negative.rb test/test_properties.rb test/test_genome.rb]],
  "control_stats" => ["lib/yarvpilled/control.rb", %w[entropy permutation_p permutation_p_mc binom bootstrap_ci permutation_p_exact mean sd cohens_d fmt_p min_p holm],
                      %w[test/test_stats.rb test/test_control_and_bench.rb test/test_claims.rb]],
  "state_digest" => ["lib/yarvpilled/state_digest.rb", %w[world], %w[test/test_differential.rb test/test_properties.rb test/test_claims.rb]]
}.freeze

OPERATORS = [
  [/(?<=\s)\+(?=\s)/, "-"], [/(?<=\s)-(?=\s)/, "+"], [/(?<=\s)\*(?=\s)/, "/"], [/(?<=\s)\/(?=\s)/, "*"],
  [/(?<=\s)<(?=\s)/, "<="], [/(?<=\s)<=(?=\s)/, "<"], [/(?<=\s)>(?=\s)/, ">="], [/(?<=\s)>=(?=\s)/, ">"],
  [/(?<=\s)==(?=\s)/, "!="], [/(?<=\s)!=(?=\s)/, "=="], [/(?<=\s)&&(?=\s)/, "||"], [/(?<=\s)\|\|(?=\s)/, "&&"],
  [/(?<=\s)%(?=\s)/, "*"], [/(?<=\s)&(?=\s)/, "|"], [/(?<=\s)>>(?=\s)/, "<<"],
  [/\btrue\b/, "false"], [/\bfalse\b/, "true"], [/\.max\b/, ".min"], [/\.min\b/, ".max"],
  [/(?<![\w.])(\d+)(?![\w.])/, :inc], [/(?<![\w.])(\d+\.\d+)(?![\w.])/, :finc],
  [/\bunless\b/, "if"], [/(?<=\s)if(?=\s)/, "unless"], [/\.negative\?/, ".positive?"]
].freeze

# Line ranges of the named methods (def ... matching end by indentation).
def method_lines(src, names)
  lines = src.lines
  ranges = []
  lines.each_with_index do |l, i|
    m = l.match(/\A(\s*)def (?:self\.)?([\w!?]+)/) or next
    next unless names.include?(m[2])

    if l.include?(" = ") && !l.rstrip.end_with?("do") # endless method
      ranges << (i..i)
      next
    end
    ind = m[1]
    j = (i + 1...lines.size).find { lines[_1].match?(/\A#{ind}end\b/) } or next
    ranges << (i..j)
  end
  ranges.flat_map(&:to_a).uniq.sort
end

def mutants_for(src, line_nos)
  lines = src.lines
  out = []
  line_nos.each do |n|
    code = lines[n].sub(/\s+#.*\z/, "") # never mutate comments
    next if code.strip.start_with?("#", "raise", "def ") && !code.include?(" = ")

    OPERATORS.each do |re, rep|
      code.to_enum(:scan, re).map { Regexp.last_match }.each do |m|
        next if m.pre_match.count('"').odd? # inside a string literal

        repl = case rep
               when :inc then (m[1].to_i + 1).to_s
               when :finc then (m[1].to_f * 1.25).to_s
               else rep
               end
        mutated = m.pre_match + repl + m.post_match + lines[n][code.size..].to_s
        next if mutated == lines[n]

        out << { line: n + 1, from: m[0], to: repl, text: lines[n].strip, src: lines.dup.tap { _1[n] = mutated }.join }
      end
    end
  end
  out
end

def run_tests(lib, tests, timeout)
  cmd = [RUBY, "-I#{File.join(ROOT, 'test')}", "-e", "ARGV.each { require File.expand_path(_1) }", *tests.map { File.join(ROOT, _1) }]
  env = { "YP_LIB" => lib, "PROP_SCALE" => ENV.fetch("PROP_SCALE", "0.25"), "MT_NO_PLUGINS" => "1", "YP_MUTATING" => "1" }
  pid = nil
  Open3.popen2e(env, *cmd, chdir: ROOT, pgroup: true) do |_in, io, th|
    pid = th.pid
    reader = Thread.new { io.read }
    unless th.join(timeout)
      Process.kill("KILL", -pid)
      th.join
      reader.join
      return :timeout
    end
    reader.join
    th.value.success? ? :survived : :killed
  end
end

t_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
work = Dir.mktmpdir("yp-mutate-") rescue (require "tmpdir"; Dir.mktmpdir("yp-mutate-"))
results = {}
TARGETS.each do |name, (file, methods, tests)|
  next if opts[:only] && !name.include?(opts[:only])

  src = File.read(File.join(ROOT, file))
  all = mutants_for(src, method_lines(src, methods))
  picked = all.size <= opts[:max] ? all : all.each_slice((all.size.to_f / opts[:max]).ceil).map(&:first)
  base_lib = File.join(work, "base")
  FileUtils.rm_rf(base_lib)
  FileUtils.cp_r(File.join(ROOT, "lib"), base_lib)
  abort "baseline tests fail for #{name}; fix them before mutation testing" unless run_tests(base_lib, tests, opts[:timeout] * 3) == :survived

  queue = Queue.new
  picked.each_with_index { |m, i| queue << [m, i] }
  outcomes = Array.new(picked.size)
  Array.new(opts[:jobs]) do |w|
    Thread.new do
      lib = File.join(work, "w#{w}")
      FileUtils.rm_rf(lib)
      FileUtils.cp_r(File.join(ROOT, "lib"), lib)
      target = File.join(lib, file.delete_prefix("lib/"))
      while (job = queue.pop(true) rescue nil)
        m, i = job
        File.write(target, m[:src])
        outcomes[i] = run_tests(lib, tests, opts[:timeout])
        File.write(target, src)
      end
    end
  end.each(&:join)

  killed = outcomes.count { _1 != :survived }
  survivors = picked.each_with_index.select { |_, i| outcomes[i] == :survived }.map { |m, _| m.slice(:line, :from, :to, :text) }
  results[name] = { file: file, methods: methods, tests: tests, mutants_total: all.size, mutants_run: picked.size,
                    killed: killed, timeouts: outcomes.count(:timeout), survived: survivors.size,
                    score: picked.empty? ? nil : (killed.to_f / picked.size).round(4), survivors: survivors }
  puts format("%-15s %4d/%-4d killed (%5.1f%%), %d survived, %d timeouts (%d mutants total)",
              name, killed, picked.size, 100.0 * killed / [picked.size, 1].max, survivors.size, outcomes.count(:timeout), all.size)
end
FileUtils.rm_rf(work)

run = results.values.sum { _1[:mutants_run] }
kill = results.values.sum { _1[:killed] }
summary = { tool: "tools/mutate.rb", date_utc: Time.now.utc.iso8601, ruby: RUBY_DESCRIPTION,
            seconds: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t_start).round(1),
            prop_scale: ENV.fetch("PROP_SCALE", "0.25"), mutants_run: run, killed: kill,
            score: run.zero? ? nil : (kill.to_f / run).round(4), targets: results }
FileUtils.mkdir_p(File.dirname(opts[:out]))
File.write(opts[:out], JSON.pretty_generate(summary))
puts format("TOTAL %d/%d killed = %.1f%% mutation score -> %s", kill, run, 100.0 * kill / [run, 1].max, opts[:out])
