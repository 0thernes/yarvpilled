# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/prop"
require_relative "support/reference_world"
require_relative "support/world_driver"

# Layer 5: differential testing. Every backend (C, asm, Rust, pure Ruby) and a
# deliberately simple O(n^2) reference stepper run the same random worlds;
# all of them must agree bit for bit on sensors, births/deaths, and the full
# state digest after every tick. Claim: C-EQ-1.
class TestDifferential < Minitest::Test
  CASES = 300

  def backends
    @backends ||= %i[c asm rust ruby].select { Yarvpilled::World.available?(_1) }
  end

  def build(kind, spec)
    if kind == :ref
      Yarvpilled::ReferenceWorld.new(spec[:w], spec[:h], spec[:fcell], spec[:cap])
    else
      Yarvpilled::World.build(kind, spec[:w], spec[:h], spec[:fcell], spec[:cap])
    end
  end

  def trace(kind, spec)
    w = build(kind, spec)
    log = [WorldDriver.setup(w, spec)]
    WorldDriver.run(w, spec) { |t, world, out, _a, b, d| log << [t, out.first(world.used * 6), b, d, WorldDriver.digest(world)] }
    log
  end

  def test_all_backends_and_reference_agree_on_random_worlds
    kinds = backends + [:ref]
    Prop.check("differential", cases: CASES) do |g|
      spec = g.world_spec
      ref = trace(:ref, spec)
      (kinds - [:ref]).each do |k|
        got = trace(k, spec)
        got.zip(ref).each_with_index do |(a, b), step|
          assert_equal b, a, "#{k} diverged from the reference at step #{step} (#{spec.slice(:w, :h, :fcell, :cap)})"
        end
      end
    end
    assert_equal CASES * Prop::SCALE, Prop.counts["differential"]
  end

  # The reference must not be trivially equal: a one-character change to its
  # collision rule has to be detected by the same comparison.
  def test_reference_disagrees_when_collision_rule_changes
    spec = { w: 96.0, h: 96.0, fcell: 8, cap: 4, fert: "\0" * 144, food: 50,
             spawns: [[40.0, 40.0, 0, 500, 0, 0], [43.0, 40.0, 32, 500, 0, 0]], ticks: 1, thresh: 2000, actions_seed: 1 }
    good = trace(:ruby, spec)
    patched = Class.new(Yarvpilled::ReferenceWorld) do
      def collide = nil # pretend collisions do not exist
    end
    w = patched.new(96.0, 96.0, 8, 4)
    WorldDriver.setup(w, spec)
    WorldDriver.run(w, spec)
    refute_equal good.last.last, WorldDriver.digest(w)
  end
end
