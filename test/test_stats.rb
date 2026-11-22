# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/prop"

# The statistics behind C-CTRL-*: hand-computed values, an independent
# brute-force permutation test, and Monte Carlo vs exact agreement.
class TestStats < Minitest::Test
  C = Yarvpilled::Control

  def test_moments_and_effect_size_by_hand
    a = [1, 2, 3, 4]
    b = [2, 4, 6, 8]
    assert_in_delta 2.5, C.mean(a), 1e-12
    assert_in_delta Math.sqrt(5.0 / 3), C.sd(a), 1e-12
    assert_in_delta Math.sqrt(20.0 / 3), C.sd(b), 1e-12
    assert_in_delta(-2.5 / Math.sqrt(25.0 / 6), C.cohens_d(a, b), 1e-12)
    assert_in_delta 0.0, C.cohens_d([3, 3], [3, 3]), 0
  end

  def test_entropy_by_hand
    assert_in_delta 1.0, C.entropy([7, 7]), 1e-12
    assert_in_delta 2.0, C.entropy([1, 1, 1, 1]), 1e-12
    assert_in_delta 0.0, C.entropy([5, 0]), 1e-12
    assert_in_delta 0.0, C.entropy([]), 1e-12
    assert_in_delta 1.5, C.entropy([2, 1, 1]), 1e-12
  end

  def test_holm_by_hand
    assert_equal [0.06, 0.003, 0.06], C.holm([0.04, 0.001, 0.03]).map { _1.round(9) }
    assert_equal [1.0, 1.0], C.holm([0.6, 0.9])
  end

  def test_fmt_p
    assert_equal "6.0e-05", C.fmt_p(6.0e-5)
    assert_equal "0.0077", C.fmt_p(0.0077)
    assert_equal "1.0000", C.fmt_p(1.0)
  end

  # Independent brute force: enumerate label bitmasks directly.
  def brute_p(a, b)
    all = a + b
    n = all.size
    obs = (a.sum.to_f / a.size - b.sum.to_f / b.size).abs
    total = extreme = 0
    (0...(1 << n)).each do |m|
      next unless m.to_s(2).count("1") == a.size

      ga = all.each_index.select { m[_1] == 1 }.map { all[_1] }
      gb = all.each_index.reject { m[_1] == 1 }.map { all[_1] }
      total += 1
      extreme += 1 if (ga.sum.to_f / ga.size - gb.sum.to_f / gb.size).abs >= obs - 1e-12
    end
    extreme.to_f / total
  end

  def test_exact_permutation_matches_brute_force
    Prop.check("perm-exact", cases: 150) do |g|
      na = g.int(2, 6)
      nb = g.int(2, 6)
      a = Array.new(na) { g.int(0, 9) }
      b = Array.new(nb) { g.int(0, 9) + g.int(0, 3) }
      assert_in_delta brute_p(a, b), C.permutation_p_exact(a, b), 1e-12, "#{a} vs #{b}"
    end
  end

  def test_monte_carlo_agrees_with_exact
    rng = Random.new(3)
    5.times do
      a = Array.new(7) { rng.rand }
      b = Array.new(7) { rng.rand + 0.3 }
      exact = C.permutation_p_exact(a, b)
      mc = C.permutation_p_mc(a, b, mc: 20_000, seed: 7)
      tol = 4 * Math.sqrt(exact * (1 - exact) / 20_000) + 1e-3
      assert_in_delta exact, mc, tol
      assert_equal mc, C.permutation_p_mc(a, b, mc: 20_000, seed: 7), "MC p must be reproducible for a seed"
    end
    assert_in_delta 2.0 / 252, C.permutation_p_mc([10, 11, 12, 13, 14], [1, 2, 3, 4, 5], mc: 20_000), 0.003
  end

  def test_uses_monte_carlo_only_above_the_exact_limit
    assert_operator C.binom(20, 10), :<=, C::EXACT_LIMIT
    assert_operator C.binom(40, 20), :>, C::EXACT_LIMIT
    assert_in_delta 2.0 / C.binom(20, 10), C.min_p(10), 1e-15
    assert_in_delta 1.0 / (1 + C::MC_PERMUTATIONS), C.min_p(20), 1e-15
  end

  def test_bootstrap_ci
    a = [5.1, 4.9, 5.6, 5.0, 4.7, 5.3, 5.8, 4.6]
    b = [4.4, 4.5, 4.2, 4.7, 4.3, 4.6, 4.1, 4.5]
    ci = C.bootstrap_ci(a, b, reps: 4000)
    obs = C.mean(a) - C.mean(b)
    assert_operator ci[:diff][0], :<, obs
    assert_operator ci[:diff][1], :>, obs
    assert_operator ci[:diff][0], :>, 0, "a clear difference must exclude 0"
    assert_operator ci[:d][0], :<, C.cohens_d(a, b)
    assert_equal ci, C.bootstrap_ci(a, b, reps: 4000), "bootstrap must be reproducible for a seed"
    same = C.bootstrap_ci([2.0] * 5, [2.0] * 5, reps: 500)
    assert_equal [0.0, 0.0], same[:diff]
    overlap = C.bootstrap_ci([1, 2, 3, 4, 5], [1, 2, 3, 4, 5], reps: 2000)
    assert_operator overlap[:diff][0], :<, 0
    assert_operator overlap[:diff][1], :>, 0
  end
end
