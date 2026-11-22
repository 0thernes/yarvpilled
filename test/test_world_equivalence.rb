# frozen_string_literal: true

require_relative "test_helper"

# The C extension and the pure-Ruby world must be bit-for-bit identical, so
# the benchmark compares equal work.
class TestWorldEquivalence < Minitest::Test
  def setup
    skip "C extension not compiled" unless Yarvpilled::Native::AVAILABLE
  end

  def test_c_and_ruby_worlds_agree_for_300_ticks
    worlds = [Yarvpilled::Native::World.new(768, 512, 8, 400), Yarvpilled::WorldRuby.new(768, 512, 8, 400)]
    fert = Array.new(96 * 64) { |i| (i * 37) % 200 }.pack("C*")
    rng = Random.new(1)
    spawns = Array.new(250) { [rng.rand * 768, rng.rand * 512, rng.rand(64), 400, rng.rand(5), rng.rand(4)] }
    worlds.each do |w|
      w.fertility = fert
      w.fill_food(60)
      spawns.each { |s| w.spawn(*s) }
    end
    outs = worlds.map { Array.new(400 * 6, 0) }
    300.times do |t|
      res = worlds.each_with_index.map do |w, k|
        w.sense(outs[k])
        w.act(Array.new(w.used) { |i| outs[k][i * 6] + outs[k][i * 6 + 4] + t }, 700)
      end
      assert_equal res[0], res[1], "births/deaths diverged at tick #{t}"
      assert_equal outs[0], outs[1], "sensors diverged at tick #{t}"
      res[0][0].each { |i| worlds.each { |w| w.spawn(10.0 + i, 20.0, i, w.split(i), 1, 2) } }
    end
    assert_equal worlds[0].snapshot, worlds[1].snapshot
    assert_equal worlds[0].food_bytes, worlds[1].food_bytes
    assert_equal worlds[0].stats, worlds[1].stats
  end
end
