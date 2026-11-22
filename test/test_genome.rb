# frozen_string_literal: true

require_relative "test_helper"

class TestGenome < Minitest::Test
  G = Yarvpilled::Genome

  def test_seed_compiles_to_a_real_iseq_and_behaves
    g = G.seed
    assert_kind_of RubyVM::InstructionSequence, g.iseq
    assert_equal 0, g.brain.call(200, 0, 0, 0, 0, 0), "food ahead -> graze"
    assert_equal 1, g.brain.call(0, 50, 10, 0, 0, 0), "more food left -> turn left"
    assert_equal 2, g.brain.call(0, 10, 50, 0, 0, 0), "more food right -> turn right"
  end

  def test_histogram_and_length_match_the_disasm
    g = G.seed
    ops = g.disasm.lines.grep(/\A\d{4} /).map { _1.split[1].to_sym }
    assert_equal ops.tally, g.histogram.to_h
    last = g.disasm.lines.grep(/\A\d{4} /).last
    assert_operator g.bytecode_len, :>, last[0, 4].to_i
  end

  def test_binary_roundtrip_is_the_genome
    g = G.seed.mutate(Random.new(5))
    clone = G.brain_from_binary(g.binary)
    rng = Random.new(9)
    50.times do
      args = Array.new(6) { rng.rand(256) }
      assert_equal g.brain.call(*args), clone.call(*args)
    end
    assert_equal RubyVM::InstructionSequence.of(clone).to_a[13], g.iseq.to_a[13]
  end

  def test_mutation_always_yields_valid_integer_programs
    rng = Random.new(42)
    g = G.seed
    200.times do
      g = g.mutate(rng, dreamer: -> { [rng.rand(64), "Test=>1"] })
      out = g.brain.call(*Array.new(6) { rng.rand(256) })
      assert_kind_of Integer, out
    end
  end

  def test_traits_derive_only_from_bytecode
    a = G.new(G::SEED_STMTS, G::SEED_RET)
    b = G.new(G::SEED_STMTS, G::SEED_RET)
    assert_equal a.traits, b.traits
    assert_equal 3 + (a.histogram.size % 5), a.traits[:sides]
  end
end
