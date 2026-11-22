# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/prop"
require_relative "support/world_driver"
require_relative "support/genome_junk"

# Layer 4: property-based tests over thousands of generated worlds and
# genomes (stdlib-only generator in test/support/prop.rb). Claims: C-INV-1..5.
class TestProperties < Minitest::Test
  W = Yarvpilled::WorldRuby
  G = Yarvpilled::Genome
  BITE = [9, 4, 4, 4].freeze

  def kinds = %i[c asm rust ruby].select { Yarvpilled::World.available?(_1) }
  def ivar(w, name) = w.instance_variable_get(name)

  # C-INV-1 energy accounting: for every creature on every tick,
  #   Δenergy = take + take/2 - (3 + cost + (action == sprint ? 3 : 0))
  # with 0 <= take <= bite(action), and the takes sum exactly to Δeaten.
  # Food is conserved: Δfood = regrowth - Δeaten + death refunds (<= 40 each).
  # (Checked on the Ruby world, whose internals are visible; the other
  # backends are bit-identical to it, see test_differential.rb.)
  def test_energy_accounting
    Prop.check("energy", cases: 1500) do |g|
      spec = g.world_spec
      w = W.new(spec[:w], spec[:h], spec[:fcell], spec[:cap])
      WorldDriver.setup(w, spec)
      rng = Random.new(spec[:actions_seed])
      out = Array.new(spec[:cap] * 6, 0)
      spec[:ticks].times do
        w.sense(out)
        e0 = ivar(w, :@energy).dup
        alive0 = ivar(w, :@alive).dup
        cost = ivar(w, :@cost).dup
        food0 = ivar(w, :@food).sum
        regrow = ivar(w, :@facc).zip(ivar(w, :@fert), ivar(w, :@food)).sum { |acc, f, fd| [fd + ((acc + f) >> 8), 255].min - fd }
        st0 = w.stats
        actions = Array.new(w.used) { rng.rand(-8..40) }
        w.act(actions, spec[:thresh])
        st1 = w.stats
        takes = 0
        w.used.times do |i|
          next unless alive0[i]

          a = actions[i] & 3
          gain = ivar(w, :@energy)[i] - e0[i] + 3 + cost[i] + (a == 3 ? 3 : 0)
          take = (0..BITE[a]).find { |t| t + t / 2 == gain }
          refute_nil take, "creature #{i}: energy change #{gain} is not take + take/2 for any legal take"
          takes += take
        end
        dead = st1[:deaths] - st0[:deaths]
        assert_equal st1[:eaten] - st0[:eaten], takes
        dfood = st1[:food] - food0
        assert_operator dfood, :<=, regrow - takes + 40 * dead
        assert_operator dfood, :>=, regrow - takes
        assert_equal regrow - takes, dfood if dead.zero?
      end
    end
  end

  # C-INV-2 bounds, on every backend: positions inside the torus, headings in
  # 0..63, food bytes, sensor ranges, population <= capacity.
  def test_bounds_hold_on_every_backend
    ks = kinds
    Prop.check("bounds", cases: 400) do |g|
      spec = g.world_spec
      ks.each do |k|
        w = Yarvpilled::World.build(k, spec[:w], spec[:h], spec[:fcell], spec[:cap])
        slots = WorldDriver.setup(w, spec)
        assert_equal [spec[:spawns].size, spec[:cap]].min, slots.compact.size, "#{k}: spawn must fill exactly up to capacity"
        assert(slots.drop(spec[:cap]).all?(&:nil?), "#{k}: spawn past capacity must return nil")
        WorldDriver.run(w, spec) do |_t, world, out, _a, births, deaths|
          snap = world.snapshot.each_slice(8).to_a
          assert_operator snap.size, :<=, spec[:cap]
          assert_operator world.used, :<=, spec[:cap]
          snap.each do |_i, x, y, hd, _e, _s, age, la|
            assert(x >= 0 && x < spec[:w] && y >= 0 && y < spec[:h], "#{k}: position (#{x}, #{y}) outside #{spec[:w]}x#{spec[:h]}")
            assert_includes 0..63, hd
            assert_includes 0..899, age
            assert_includes 0..3, la
          end
          out.each_slice(6).first(world.used).each do |fa, fl, fr, en, cr, ag|
            [fa, fl, fr, en, ag].each { |v| assert_includes 0..255, v }
            assert_includes 0..15, cr
          end
          assert_empty births & deaths
        end
      end
    end
  end

  # C-INV-3 determinism: the same spec twice gives the same digest, on every
  # backend, with a GC in between (no hidden global state).
  def test_determinism
    ks = kinds
    Prop.check("determinism", cases: 300) do |g|
      spec = g.world_spec
      ks.each do |k|
        a = WorldDriver.run(Yarvpilled::World.build(k, spec[:w], spec[:h], spec[:fcell], spec[:cap]).tap { WorldDriver.setup(_1, spec) }, spec)
        GC.start
        b = WorldDriver.run(Yarvpilled::World.build(k, spec[:w], spec[:h], spec[:fcell], spec[:cap]).tap { WorldDriver.setup(_1, spec) }, spec)
        assert_equal WorldDriver.digest(a), WorldDriver.digest(b), "#{k} is not deterministic"
      end
    end
  end

  # C-INV-4 every mutated genome compiles to a brain that returns an Integer
  # for any sensor input, survives the to_binary round trip, and is accepted
  # by its own grammar.
  def test_mutation_chains_always_yield_valid_brains
    Prop.check("genomes", cases: 2000) do |g|
      genome = G.seed
      g.int(1, 25).times do
        dreamer = g.bool ? -> { [g.int(-G::INT_LIMIT, G::INT_LIMIT), "dream"] } : nil
        genome = genome.mutate(g.rng, dreamer: dreamer)
      rescue G::InvalidGenome => e
        flunk "mutate produced a genome its own grammar rejects: #{e.message}"
      end
      args = Array.new(6) { g.int(0, 255) }
      res = genome.brain.call(*args)
      assert_kind_of Integer, res
      assert_equal res, G.brain_from_binary(genome.binary).call(*args), "binary round trip changed behaviour"
      assert G.validate!(genome.stmts, genome.ret)
    end
  end

  # C-INV-5 random junk trees either validate (and then compile and return an
  # Integer) or raise InvalidGenome. Nothing else (SyntaxError, NameError,
  # ZeroDivisionError, TypeError, ...) may escape.
  def test_random_trees_validate_or_reject_cleanly
    accepted = 0
    Prop.check("junk-genomes", cases: 3000) do |g|
      stmts, ret = GenomeJunk.tree(g)
      begin
        genome = G.new(stmts, ret)
      rescue G::InvalidGenome
        next
      end
      accepted += 1
      assert_kind_of Integer, genome.brain.call(*Array.new(6) { g.int(0, 255) })
    end
    assert_operator accepted, :>, 50, "generator too hostile: almost nothing was valid"
  end
end
