# frozen_string_literal: true

# A tiny, stdlib-only property-based testing helper.
#
#   Prop.check("name", cases: 2000) { |g| ... assert ... }
#
# Every case gets its own deterministic Random derived from (PROP_SEED, name,
# case index), so a failure message names the exact case and it reproduces with
#   PROP_SEED=<seed> PROP_ONLY=<case> ruby -Itest test/test_properties.rb
# PROP_SCALE multiplies every case count (e.g. PROP_SCALE=10 for a soak run).
require "zlib"

module Prop
  SEED = Integer(ENV.fetch("PROP_SEED", "20261122"))
  SCALE = Float(ENV.fetch("PROP_SCALE", "1"))
  @counts = Hash.new(0)

  class << self
    attr_reader :counts

    def check(name, cases:)
      n = [(cases * SCALE).round, 1].max
      only = ENV["PROP_ONLY"]&.then { Integer(_1) }
      n.times do |k|
        next if only && k != only

        g = Gen.new(Random.new(Zlib.crc32("#{SEED}:#{name}:#{k}")))
        begin
          yield g
        rescue Minitest::Assertion, StandardError => e
          raise e.class, "#{e.message}\n[property #{name.inspect} failed on case #{k}; reproduce: PROP_SEED=#{SEED} PROP_ONLY=#{k}]", e.backtrace
        end
        @counts[name] += 1
      end
    end
  end

  # Value generators. Biased towards edges (0, limits) the way hand-written
  # property libraries are, because edges are where bugs live.
  class Gen
    attr_reader :rng

    def initialize(rng) = @rng = rng
    def int(lo, hi) = rng.rand(10).zero? ? [lo, hi].sample(random: rng) : lo + rng.rand(hi - lo + 1)
    def float(lo, hi) = rng.rand(10).zero? ? lo.to_f : lo + rng.rand * (hi - lo)
    def bool = rng.rand(2).zero?
    def pick(xs) = xs.sample(random: rng)
    def bytes(n, max = 255) = Array.new(n) { int(0, max) }.pack("C*")

    # A random but valid world: size, food grid, capacity, fertility, food,
    # creatures (some deliberately past capacity) and a schedule of actions.
    def world_spec
      w = pick([72.0, 96.0, float(72, 260), int(3, 10) * 24.0])
      h = pick([72.0, 96.0, float(72, 260), int(3, 10) * 24.0])
      fcell = int(1, 16)
      fcell = int(4, 16) if (w / fcell).to_i * (h / fcell).to_i > 6000
      cap = int(1, 48)
      fw = (w / fcell).to_i
      fh = (h / fcell).to_i
      clustered = bool # many creatures within a few units: exercises collisions
      spawns = Array.new(int(0, cap + 4)) do
        x = clustered ? 30 + float(0, 12) : float(-w, 2 * w - 1e-9)
        y = clustered ? 30 + float(0, 12) : float(-h, 2 * h - 1e-9)
        [x, y, int(0, 1000), int(-20, 900), int(0, 9), pick([0, 1, 2, 5, int(0, 40)])]
      end
      { w: w, h: h, fcell: fcell, cap: cap, fert: bytes(fw * fh), food: int(0, 255),
        spawns: spawns, ticks: int(1, 12), thresh: int(50, 1200), actions_seed: rng.rand(1 << 30) }
    end
  end
end
