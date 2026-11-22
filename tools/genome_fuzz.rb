# frozen_string_literal: true

# Time-bounded genome fuzzer (layer 7). Three generators:
#   junk    hostile random trees (test/support/genome_junk.rb)
#   mutate  long mutation chains from the seed genome, with dreamed constants
#   splice  grammar-valid subtrees grafted into hostile positions
# Every candidate must either raise Genome::InvalidGenome, or compile to a
# brain that returns an Integer for random sensor input, survive the binary
# round trip, and render to source without any identifier outside the
# whitelist. Anything else is a finding, recorded with its input.
#
#   ruby tools/genome_fuzz.rb [--seconds=60] [--seed=1] [--out=out/genome_fuzz.json]
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
Warning[:experimental] = false
require "json"
require "time"
require "fileutils"
require "yarvpilled"
require_relative "../test/support/prop"
require_relative "../test/support/genome_junk"

secs = 60
seed = 1
out = File.expand_path("../out/genome_fuzz.json", __dir__)
ARGV.each do |a|
  case a
  when /\A--seconds=(\d+)\z/ then secs = Integer(Regexp.last_match(1))
  when /\A--seed=(\d+)\z/ then seed = Integer(Regexp.last_match(1))
  when /\A--out=(.+)\z/ then out = Regexp.last_match(1)
  else abort "usage: ruby tools/genome_fuzz.rb [--seconds=N] [--seed=N] [--out=FILE]"
  end
end

G = Yarvpilled::Genome
ALLOWED = /\A(?:fa|fl|fr|en|cr|ag|t0|t1|t2|t3|max|min)\z/
g = Prop::Gen.new(Random.new(seed))
counts = Hash.new(0)
findings = []
t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
deadline = t0 + secs

check = lambda do |kind, stmts, ret|
  genome = G.new(stmts, ret)
  args = Array.new(6) { g.int(0, 255) }
  r = genome.brain.call(*args)
  raise "brain returned #{r.class}" unless r.is_a?(Integer)
  raise "binary round trip changed the result" unless G.brain_from_binary(genome.binary).call(*args) == r

  idents = genome.source.scan(/[A-Za-z_]\w*/).uniq
  bad = idents.reject { ALLOWED.match?(_1) }
  raise "rendered source contains #{bad.inspect}" unless bad.empty?

  counts["#{kind}_accepted"] += 1
rescue G::InvalidGenome
  counts["#{kind}_rejected"] += 1
rescue StandardError, ScriptError, SystemStackError => e
  counts["#{kind}_FINDING"] += 1
  findings << { kind: kind, error: "#{e.class}: #{e.message}"[0, 300], stmts: stmts.inspect[0, 2000], ret: ret.inspect[0, 2000] } if findings.size < 50
end

splice = lambda do
  base = G.seed
  g.int(1, 6).times { base = base.mutate(g.rng) }
  host = GenomeJunk.expr(g, 3)
  graft = g.bool ? base.ret : GenomeJunk.expr(g, 2)
  [[*base.stmts], g.bool ? [:op, g.pick(G::OPS), graft, host] : [:if, [:cmp, :<, graft, host], host, graft]]
end

genome = G.seed
while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
  check.call(:junk, *GenomeJunk.tree(g))
  dreamer = g.bool ? -> { [g.int(-G::INT_LIMIT, G::INT_LIMIT), "dream"] } : nil
  begin
    genome = genome.mutate(g.rng, dreamer: dreamer)
    genome = G.seed if g.int(0, 200).zero?
    check.call(:mutate, genome.stmts, genome.ret)
  rescue StandardError => e
    counts["mutate_FINDING"] += 1
    findings << { kind: :mutate, error: "#{e.class}: #{e.message}"[0, 300], stmts: genome.stmts.inspect, ret: genome.ret.inspect }
    genome = G.seed
  end
  check.call(:splice, *splice.call)
end

elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
total = counts.values.sum
res = { tool: "tools/genome_fuzz.rb", seed: seed, seconds: elapsed.round(1), candidates: total,
        per_second: (total / elapsed).round, counts: counts.sort.to_h, findings: findings,
        ruby: RUBY_DESCRIPTION, date_utc: Time.now.utc.iso8601 }
FileUtils.mkdir_p(File.dirname(out))
File.write(out, JSON.pretty_generate(res))
puts JSON.pretty_generate(res.except(:findings))
puts findings.empty? ? "no findings" : "#{findings.size} FINDINGS (see #{out})"
exit(findings.empty? ? 0 : 1)
