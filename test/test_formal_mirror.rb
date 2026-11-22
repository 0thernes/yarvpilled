# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/prop"
require "open3"

# Layer 9 bridge: the Lean spec (formal/lean) proves properties of `tick1`, the
# integer step of one creature alone in one food cell. formal/lean/Mirror.lean
# runs that exact Lean function; here every backend runs the same scenario in
# a 72x72 world with a single 72-unit food cell (so movement never changes the
# cell) and must match the Lean output tick for tick. Claim: C-FORMAL-2.
# Skipped when Lean (lake) is not installed.
class TestFormalMirror < Minitest::Test
  LEAN_DIR = File.expand_path("../formal/lean", __dir__)
  CASES = 1500
  NO_PRELOAD = { "LD_PRELOAD" => nil }.freeze # lake must not inherit the sanitizer runtime (rake sanitize)

  def lake
    @lake ||= [ENV["LAKE"], "lake", File.expand_path("~/.elan/bin/lake")].compact.find do |c|
      system(NO_PRELOAD, c, "--version", out: File::NULL, err: File::NULL, chdir: LEAN_DIR)
    rescue SystemCallError
      false
    end
  end

  def test_backends_match_the_lean_mirror
    skip "Lean/lake not installed (see formal/lean/README.md)" unless lake

    cases = []
    Prop.check("lean-mirror", cases: CASES) do |g|
      cases << [g.int(0, 255), g.int(0, 255), g.int(-10, 400), g.int(0, 12), g.int(50, 400),
                *Array.new(g.int(1, 40)) { g.int(0, 3) }]
    end
    out, err, st = Open3.capture3(NO_PRELOAD, lake, "env", "lean", "--run", "Mirror.lean",
                                  stdin_data: cases.map { _1.join(" ") }.join("\n") + "\n", chdir: LEAN_DIR)
    assert st.success?, err
    lean = out.split(".\n").map { _1.split("\n") }
    assert_equal cases.size, lean.size

    kinds = %i[c asm rust ruby].select { Yarvpilled::World.available?(_1) }
    kinds.each do |k|
      cases.each_with_index do |(food, fert, energy, cost, thresh, *acts), n|
        assert_equal lean[n], trace(k, food, fert, energy, cost, thresh, acts, n), "#{k} != Lean on case #{n}"
      end
    end
  end

  private

  def trace(kind, food, fert, energy, cost, thresh, acts, n)
    w = Yarvpilled::World.build(kind, 72, 72, 72, 1)
    w.fertility = [fert].pack("C")
    w.fill_food(food)
    w.spawn(36.0, 36.0, n % 64, energy, 0, cost)
    out = Array.new(6, 0)
    acts.map do |a|
      w.sense(out)
      births, = w.act([a], thresh)
      snap = w.snapshot
      st = w.stats
      e = snap.empty? ? "-" : snap[4].to_s
      "#{out[0]} #{out[3]} #{out[5]} | #{e} #{st[:food]} #{st[:eaten]} #{!snap.empty?} #{births.include?(0)}"
    end
  end
end
