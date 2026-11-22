# frozen_string_literal: true

require_relative "test_helper"

class TestSimulation < Minitest::Test
  def test_tracepoint_rewrites_a_live_method_mid_call
    sim = Yarvpilled::Simulation.new(seed: 11)
    sim.step! until sim.rewrite_log.any? || sim.tick > 400
    rec = sim.rewrite_log.first
    refute_nil rec, "expected a TracePoint gene transfer within 400 ticks"
    assert_equal :think, rec[:method]
    assert rec[:stack].any? { _1.include?("attend!") }, "hook ran inside the creature's think call"
    sp = sim.species[rec[:species]]
    live = RubyVM::InstructionSequence.of(sp.mind.class.instance_method(:think))
    assert_equal sp.genome.iseq.to_a[13], live.to_a[13], "method now runs the donor genome's ISeq"
    refute_nil rec[:inflight_result]
    refute_nil rec[:next_result]
  ensure
    sim&.close
  end

  def test_events_ractors_and_gc_compact_happen_for_real
    sim = Yarvpilled::Simulation.new(seed: 11)
    160.times { sim.step! }
    assert_operator sim.votes.size, :>=, 1
    assert(sim.votes.values.flatten.all? { |v| v[:ns].positive? })
    assert_equal 1, sim.compacts
    assert_operator sim.last_compact[:considered], :>, 0
    assert_operator sim.think_calls, :>, 10_000
    assert_operator sim.fiber_switches_total, :>, 0
  ensure
    sim&.close
  end

  def test_guardrail_refinement_is_lexically_scoped
    refute_respond_to 5, :to_action, "refinement must not leak outside simulation.rb"
  end

  def test_core_is_deterministic_without_events
    a = Yarvpilled::Simulation.new(seed: 3, events_enabled: false)
    b = Yarvpilled::Simulation.new(seed: 3, events_enabled: false)
    200.times { a.step! && b.step! }
    assert_equal a.world.snapshot, b.world.snapshot
    assert_equal a.births_total, b.births_total
  end
end
