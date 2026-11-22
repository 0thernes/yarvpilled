# frozen_string_literal: true

require_relative "test_helper"

class TestControlAndBench < Minitest::Test
  C = Yarvpilled::Control

  def test_exact_permutation_test
    assert_in_delta 2.0 / 70, C.permutation_p([10, 11, 12, 13], [1, 2, 3, 4]), 1e-12 # complete separation
    assert_in_delta 1.0, C.permutation_p([1, 2, 3, 4], [1, 2, 3, 4]), 1e-12
  end

  def test_holm_adjustment_is_monotone_and_capped
    assert_equal [0.03, 0.04, 0.04], C.holm([0.01, 0.02, 0.03]).map { _1.round(6) }
    assert_equal 1.0, C.holm([0.9, 0.8]).max
  end

  def test_entropy
    assert_in_delta 1.0, C.entropy([5, 5]), 1e-12
    assert_in_delta 0.0, C.entropy([9]), 1e-12
  end

  def test_drift_control_decouples_behaviour_from_genome
    sel = Yarvpilled::Simulation.new(seed: 5, events_enabled: false)
    drift = Yarvpilled::Simulation.new(seed: 5, events_enabled: false, control: :drift)
    100.times { sel.step! && drift.step! }
    refute_equal sel.world.snapshot, drift.world.snapshot
    assert_equal sel.think_calls.positive?, drift.think_calls.positive?, "brains still execute under drift"
    fit, surv = C.assay(Yarvpilled::Genome.seed)
    assert_operator fit, :>, 0
    assert surv.between?(0.0, 1.0)
  ensure
    sel&.close
    drift&.close
  end

  def test_bench_stats
    st = Yarvpilled::Bench.stats([3, 1, 2, 10, 4])
    assert_equal 3, st[:median]
    assert_equal 1, st[:min]
    assert_equal 10, st[:max]
  end
end
