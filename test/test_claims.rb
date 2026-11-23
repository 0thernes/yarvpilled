# frozen_string_literal: true

require_relative "test_helper"
require_relative "../tools/claims"
require "open3"

# Layer 2: README numbers cannot drift from the recorded data, every claim ID
# resolves, and the claim map points at tests that exist. See CLAIMS.md.
class TestClaims < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  CL = Yarvpilled::Claims
  C = Yarvpilled::Control

  def read(f) = File.read(File.join(ROOT, f))
  def readme = @readme ||= read("README.md")
  def claims_md = @claims_md ||= read("CLAIMS.md")
  def control = @control ||= JSON.parse(read("docs/control.json"), symbolize_names: true)
  def bench = @bench ||= JSON.parse(read("docs/bench.json"), symbolize_names: true)

  # C-VER-1 and everything numeric in the README: generated blocks == data.
  def test_generated_blocks_match_their_data
    drift = CL.drift
    # tools/mutate.rb rewrites docs/verification/mutation.json while it runs, so the
    # evidence block is allowed to lag only inside a mutation run (all other blocks are checked).
    drift -= [["docs/verification.md", "verification-evidence"]] if ENV["YP_MUTATING"] == "1"
    assert_empty drift, "run `ruby tools/claims.rb --write` after updating docs/*.json"
    %w[speed-glance evolution-glance bench-tables bench-verdict control-table].each do |name|
      assert_includes readme, "<!-- generated:#{name} -->", "README lost its #{name} block"
    end
  end

  # Independent of tools/claims.rb: recompute a few README numbers straight from the rows.
  def test_readme_numbers_recomputed_independently
    rows = control[:rows]
    sel = rows.select { _1[:control] == "selection" }.map { _1[:fitness] }
    dri = rows.select { _1[:control] == "drift" }.map { _1[:fitness] }
    line = format("| foraging fitness (common-garden assay) | %.3f | %.3f |", sel.sum / sel.size, dri.sum / dri.size)
    assert_includes readme, line
    runs = bench[:runs].values.flatten
    assert_equal 1, runs.map { _1[:checksum] }.uniq.size, "C-BENCH-1: benchmark runs disagree"
    assert_includes readme, "`#{runs.first[:checksum]}` in all #{runs.size} runs"
    cps = bench[:runs].values.first.map { _1[:creatures_per_sec] }.sort
    assert_includes readme, "| pure Ruby interpreter | #{cps[cps.size / 2].round.to_s.reverse.scan(/\d{1,3}/).join(',').reverse} | 1.00x |"
  end

  # C-BENCH-2: one digest for every world-loop timing, and it is what the code computes today.
  def test_world_digest_pinned
    digests = bench[:runs].values.flatten.flat_map { [_1[:world_api_digest], _1[:kernel_digest]] }.compact.uniq
    assert_equal 1, digests.size
    kind = Yarvpilled::World.available?(:c) ? :c : :ruby
    w = Yarvpilled::Bench.fresh_world(kind)
    sens = Array.new(520 * 6, 0)
    acts = Array.new(520) { |i| i % 4 }
    Yarvpilled::Bench::MICRO_TICKS.times { w.sense(sens); w.act(acts, 1 << 60) }
    assert_equal digests.first, Yarvpilled::StateDigest.world(w)
  end

  # C-CTRL-2: the summary statistics recompute from the per-replicate rows.
  def test_control_statistics_recompute_from_rows
    rows = control[:rows]
    ps = []
    Yarvpilled::Control::METRICS.each_key do |k|
      st = control[:stats][k]
      assert_equal rows.select { _1[:control] == "selection" }.sort_by { _1[:seed] }.map { _1[k] }, st[:selection], k.to_s
      assert_equal rows.select { _1[:control] == "drift" }.sort_by { _1[:seed] }.map { _1[k] }, st[:drift], k.to_s
      assert_in_delta C.cohens_d(st[:selection], st[:drift]), st[:d], 1e-12, k.to_s
      ps << st[:p]
    end
    C.holm(ps).zip(control[:stats].values.map { _1[:p_holm] }).each { |a, b| assert_in_delta a, b, 1e-15 }
    %i[fitness survival mean_bytecode_len species_entropy_bits opcode_entropy_bits].each do |k|
      assert_operator control[:stats][k][:p_holm], :<, 0.05, "pre-registered hypothesis on #{k} no longer supported"
    end
  end

  # C-CTRL-3: the pre-registration commit is an ancestor of the commit that added the results.
  def test_preregistration_precedes_results
    skip "not a git checkout" unless File.directory?(File.join(ROOT, ".git"))

    git = ->(*a) { Open3.capture2("git", "-C", ROOT, *a).first.strip }
    prereg = git.("log", "--diff-filter=A", "--format=%H", "--", "docs/preregistration.md").lines.last&.strip
    results = git.("log", "--format=%H", "-S", '"seed": 220', "--", "docs/control.json").lines.last&.strip
    skip "history too shallow" if prereg.to_s.empty? || results.to_s.empty?
    refute_equal prereg, results, "pre-registration and results landed in the same commit"
    assert system("git", "-C", ROOT, "merge-base", "--is-ancestor", prereg, results), "pre-registration is not before the results"
  end

  # The claim map is consistent: IDs unique, README IDs exist, referenced tests exist.
  def test_claim_map_resolves
    ids = claims_md.scan(/^\| (C-[A-Z]+-\d+) /).flatten
    assert_equal ids.uniq, ids, "duplicate claim IDs"
    used = (readme + read("docs/verification.md")).scan(/\bC-[A-Z]+-\d+\b/).uniq
    assert_empty used - ids, "README/verification.md cite claim IDs missing from CLAIMS.md"
    claims_md.scan(/`(test_\w+\.rb)`(?: \(([^)]*)\))?/).each do |file, detail|
      path = File.join(ROOT, "test", file)
      assert File.exist?(path), "CLAIMS.md cites missing #{file}"
      detail.to_s.scan(/`(test_\w+)`/).flatten.each { |m| assert_match(/def #{m}\b/, File.read(path), "#{file} has no #{m}") }
    end
    claims_md.scan(%r{`((?:tools|fuzz|formal)/[\w/.]+)`}).flatten.uniq.each do |f|
      assert File.exist?(File.join(ROOT, f)), "CLAIMS.md cites missing #{f}"
    end
  end

  # C-VER-2: recorded verification runs report what they claim. A CBMC counterexample
  # (FAILED) is a finding and must be fixed, not recorded; a TIMEOUT is allowed but shows
  # up in the evidence table. Sanitizer and lattice runs must have passed.
  def test_recorded_verification_runs_passed
    ev = ->(f) { JSON.parse(read("docs/verification/#{f}"), symbolize_names: true) }
    if File.exist?(File.join(ROOT, "docs/verification/cbmc.json"))
      cb = ev.("cbmc.json")
      refute_empty cb[:harnesses]
      assert_empty cb[:harnesses].select { _1[:verdict] == "FAILED" }, "CBMC counterexample recorded"
      assert cb[:vacuity_guard_passed], "CBMC vacuity guard failed: a proof may be vacuous"
      cb[:harnesses].each { |h| assert_includes read("formal/cbmc/harness.c"), "void #{h[:harness]}(void)" }
    end
    if File.exist?(File.join(ROOT, "docs/verification/lattice.json"))
      la = ev.("lattice.json")
      assert la[:passed]
      assert_equal 0, la[:failures]
      assert_equal 24**4 * 16, la[:cases], "lattice enumerates every placement x action pair"
    end
    sa = ev.("sanitize.json")
    assert sa[:passed]
    assert_equal 0, sa[:sanitizer_reports]
  end
end
