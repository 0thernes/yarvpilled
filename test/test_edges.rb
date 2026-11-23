# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/reference_world"
require_relative "support/world_driver"

# Edge cases added after mutation testing (layer 6) showed the random worlds
# never reached them: the MAX_AGE boundary, the energy sensor clamp, the alive
# count returned by #sense, and out-of-range #split / #feed. Every backend and
# the reference stepper must agree, and match the values the rules give.
class TestEdges < Minitest::Test
  def kinds = %i[c asm rust ruby].select { Yarvpilled::World.available?(_1) }

  def world(kind, cap = 2)
    w = kind == :ref ? Yarvpilled::ReferenceWorld.new(72.0, 72.0, 72, cap) : Yarvpilled::World.build(kind, 72, 72, 72, cap)
    w.fertility = "\xFF".b
    w.fill_food(255)
    w
  end

  # A well-fed creature dies of old age on exactly the tick its age reaches
  # MAX_AGE (900): the condition is `age >= MAX_AGE`, not `>`.
  def test_old_age_death_tick_is_exact_on_every_backend
    ticks = (kinds + [:ref]).to_h do |k|
      w = world(k, 1)
      w.spawn(36.0, 36.0, 0, 1_000_000, 0, 0)
      out = Array.new(6, 0)
      died = nil
      1000.times do |t|
        w.sense(out)
        _b, d = w.act([0], 1 << 40)
        if d.include?(0)
          died = t + 1
          break
        end
      end
      [k, died]
    end
    assert_equal [900], ticks.values.uniq, "death ticks: #{ticks}"
  end

  # Energy sensor = energy/4 clamped to 0..255; #sense returns the alive count.
  def test_energy_sensor_clamp_and_alive_count
    kinds.each do |k|
      w = world(k, 4)
      w.spawn(10.0, 10.0, 0, 10_000, 0, 0)  # 2500 -> 255
      w.spawn(40.0, 40.0, 0, 1023, 0, 0)    # 255 exactly
      w.spawn(60.0, 20.0, 0, 1019, 0, 0)    # 254
      w.spawn(20.0, 60.0, 0, 1024, 0, 0)    # 256 -> 255 (the first value the clamp changes)
      out = Array.new(24, 0)
      assert_equal 4, w.sense(out), "#{k}: sense must return the number alive"
      assert_equal [255, 255, 254, 255], [out[3], out[9], out[15], out[21]], "#{k}: energy sensor"
      w.act([0, 0, 0, 0], 1 << 40)
      w.feed(1, -10_000) # kill slot 1
      w.act([0, 0, 0, 0], 1 << 40)
      assert_equal 3, w.sense(out), "#{k}: alive count after a death"
      assert_equal [0] * 6, out[6, 6], "#{k}: a dead slot senses zeros"
    end
  end

  # split/feed ignore out-of-range and dead slots on every backend (API guards;
  # the reference stepper only models the rules, so it is not included here).
  # The world is full, so a negative index would alias a live slot from the end.
  def test_split_and_feed_ignore_bad_slots
    kinds.each do |k|
      w = world(k, 2)
      w.spawn(10.0, 10.0, 0, 400, 0, 0)
      w.spawn(40.0, 40.0, 0, 400, 0, 0)
      [-1, -2, 2, 3, 99].each do |i|
        assert_equal 0, w.split(i), "#{k}: split(#{i})"
        assert_nil w.feed(i, 1000), "#{k}: feed(#{i})"
      end
      out = Array.new(12, 0)
      w.sense(out)
      assert_equal [100, 100], [out[3], out[9]], "#{k}: feeding a bad slot changed a live one"
      w.feed(0, 4)
      w.sense(out)
      assert_equal 101, out[3], "#{k}: feed(0) must reach slot 0"
      assert_equal 182, w.split(0), "#{k}: split gives half - 20"
      w.feed(1, -1000)
      w.act([0, 0], 1 << 40)
      assert_equal 0, w.split(1), "#{k}: split of a dead slot"
    end
  end

  # A fresh spawn reports last action 0, and missing actions default to 0.
  def test_spawn_state_and_short_action_arrays
    kinds.each do |k|
      w = world(k, 2)
      w.spawn(36.0, 36.0, 5, 1000, 3, 7)
      assert_equal [0, 36.0, 36.0, 5, 1000, 3, 0, 0], w.snapshot, "#{k}: snapshot after spawn"
      v = world(k, 2)
      v.spawn(36.0, 36.0, 5, 1000, 3, 7)
      out = Array.new(12, 0)
      [w, v].each { _1.sense(out) }
      w.act([], 1 << 40)
      v.act([0], 1 << 40)
      assert_equal WorldDriver.digest(v), WorldDriver.digest(w), "#{k}: a missing action must act like 0"
    end
  end
end
