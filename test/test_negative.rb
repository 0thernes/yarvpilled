# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "tmpdir"
require "rbconfig"

# Layer 3 (negative half): bad input is rejected cleanly, with the same error
# on every backend, before it can reach a kernel or YARV. Claims: C-NEG-1..3.
class TestNegative < Minitest::Test
  G = Yarvpilled::Genome
  ROOT = File.expand_path("..", __dir__)

  def kinds = %i[c asm rust ruby].select { Yarvpilled::World.available?(_1) }

  # C-NEG-1 world construction. Worlds smaller than 3 grid cells per axis are
  # rejected: they alias the 3x3 neighbourhood (double-counted crowding) and
  # let collision pushes escape the torus (found by the kernel fuzzer).
  def test_bad_world_params_rejected_on_every_backend
    bad = [[71.9, 100, 8, 10], [100, 4, 8, 10], [0, 0, 8, 10], [-100, 100, 8, 10],
           [Float::NAN, 100, 8, 10], [Float::INFINITY, 100, 8, 10], [2e6, 100, 8, 10],
           [100, 100, 0, 10], [100, 100, -8, 10], [100, 100, 73, 10],
           [100, 100, 8, 0], [100, 100, 8, -1], [100, 100, 8, 2_000_000]]
    kinds.each do |k|
      bad.each do |args|
        assert_raises(ArgumentError, "#{k} accepted #{args.inspect}") { Yarvpilled::World.build(k, *args) }
      end
      assert Yarvpilled::World.build(k, 72, 72, 72, 1), "#{k}: the smallest legal world must build"
    end
  end

  def test_bad_spawn_positions_rejected_without_using_a_slot
    kinds.each do |k|
      w = Yarvpilled::World.build(k, 100, 100, 10, 2)
      [[Float::NAN, 1], [1, Float::NAN], [Float::INFINITY, 1], [-100.5, 1], [200, 1], [1, 1e300]].each do |x, y|
        assert_raises(ArgumentError, "#{k} spawned at #{[x, y]}") { w.spawn(x, y, 0, 10, 0, 0) }
      end
      assert_equal 0, w.used, "#{k}: a rejected spawn must not consume a slot"
      assert_equal 0, w.spawn(-100.0, 199.9, 0, 10, 0, 0)
      assert_equal 1, w.spawn(0, 0, 0, 10, 0, 0)
      assert_nil w.spawn(0, 0, 0, 10, 0, 0), "#{k}: spawn past capacity must return nil"
    end
  end

  def test_bad_fertility_rejected
    kinds.each do |k|
      w = Yarvpilled::World.build(k, 96, 96, 8, 4)
      assert_raises(ArgumentError, k.to_s) { w.fertility = "\0" * 143 }
      assert_raises(ArgumentError, k.to_s) { w.fertility = "\0" * 145 }
    end
  end

  # C-NEG-2 genomes outside the grammar never reach the compiler.
  def test_bad_genomes_rejected
    v = [:v, :fa]
    bad = {
      "code injection in a literal" => [[], [:n, "1; system('id')"]],
      "float literal" => [[], [:n, 1.5]],
      "literal too large" => [[], [:n, G::INT_LIMIT + 1]],
      "unknown variable" => [[], [:v, :__method__]],
      "local used before definition" => [[], [:v, :t0]],
      "unknown operator" => [[], [:op, :/, v, v]],
      "modulo by zero" => [[], [:mod, v, 0]],
      "modulo by negative" => [[], [:mod, v, -3]],
      "huge shift" => [[], [:shr, v, 63]],
      "negative shift" => [[], [:shr, v, -1]],
      "wrong arity" => [[], [:op, :+, v]],
      "bad condition" => [[], [:if, v, v, v]],
      "bad comparator" => [[], [:if, [:cmp, :<=, v, v], v, v]],
      "empty node" => [[], []],
      "not an array" => [[], 42],
      "too many statements" => [Array.new(5) { |i| [:let, G::LOCALS[i % 4], v] }, v],
      "redefined local" => [[[:let, :t0, v], [:let, :t0, v]], v],
      "unknown local name" => [[[:let, :x, v]], v],
      "not a let" => [[[:def, :t0, v]], v],
      "too deep" => [[], (1..60).reduce(v) { |e, _| [:op, :+, e, [:n, 1]] }],
      "too many nodes" => [[], (1..300).reduce(v) { |e, _| [:op, :+, [:n, 1], [:op, :^, e, [:n, 2]]] }],
      "stmts not an array" => [nil, v]
    }
    bad.each do |why, (stmts, ret)|
      assert_raises(G::InvalidGenome, why) { G.new(stmts, ret) }
    end
    assert_kind_of ArgumentError, G::InvalidGenome.new
  end

  # C-NEG-3 the CLI turns bad arguments into a usage error (exit 2), not a
  # backtrace or a silently clamped run.
  def test_bad_cli_args_exit_2
    [%w[--ticks=abc], %w[--ticks=0], %w[--workers=0], %w[--world=nope], %w[--bogus], %w[stray]].each do |args|
      out, status = Open3.capture2e(RbConfig.ruby, File.join(ROOT, "yarv_brain.rb"), *args, "--out=#{Dir.tmpdir}")
      assert_equal 2, status.exitstatus, "#{args.join(' ')} -> #{out}"
      assert_match(/\Ayarv_brain: /, out)
      refute_match(/\.rb:\d+:in /, out, "no backtraces for user errors")
    end
  end
end
