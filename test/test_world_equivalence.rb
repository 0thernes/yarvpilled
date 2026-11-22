# frozen_string_literal: true

require_relative "test_helper"

# Every world backend (C, hand-written asm, Rust, pure Ruby) must be
# bit-for-bit identical, so the benchmark compares equal work.
class TestWorldEquivalence < Minitest::Test
  BACKENDS = %i[c asm rust ruby].freeze

  def setup
    skip "C extension not compiled" unless Yarvpilled::Native::AVAILABLE
  end

  def build_all
    BACKENDS.select { Yarvpilled::World.available?(_1) }.map { [_1, Yarvpilled::World.build(_1, 768, 512, 8, 400)] }
  end

  def test_all_backends_agree_for_300_ticks
    worlds = build_all
    assert_operator worlds.size, :>=, 2
    fert = Array.new(96 * 64) { |i| (i * 37) % 200 }.pack("C*")
    rng = Random.new(1)
    spawns = Array.new(250) { [rng.rand * 768, rng.rand * 512, rng.rand(64), 400, rng.rand(5), rng.rand(4)] }
    worlds.each do |_, w|
      w.fertility = fert
      w.fill_food(60)
      spawns.each { |s| w.spawn(*s) }
    end
    outs = worlds.map { Array.new(400 * 6, 0) }
    300.times do |t|
      res = worlds.each_with_index.map do |(_, w), k|
        w.sense(outs[k])
        w.act(Array.new(w.used) { |i| outs[k][i * 6] + outs[k][i * 6 + 4] + t }, 700)
      end
      worlds.each_with_index.drop(1).each do |(name, _), k|
        assert_equal res[0], res[k], "#{name}: births/deaths diverged from C at tick #{t}"
        assert_equal outs[0], outs[k], "#{name}: sensors diverged from C at tick #{t}"
      end
      res[0][0].each { |i| worlds.each { |_, w| w.spawn(10.0 + i, 20.0, i, w.split(i), 1, 2) } }
    end
    ref = worlds.first[1]
    worlds.drop(1).each do |name, w|
      assert_equal ref.snapshot, w.snapshot, "#{name} snapshot"
      assert_equal ref.food_bytes, w.food_bytes, "#{name} food"
      assert_equal ref.stats, w.stats, "#{name} stats"
    end
  end

  def test_backends_report_themselves
    build_all.each { |name, w| assert_equal name, w.backend if w.respond_to?(:backend) }
  end
end
