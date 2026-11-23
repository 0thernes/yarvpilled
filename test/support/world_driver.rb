# frozen_string_literal: true

require "yarvpilled/state_digest"

# Drives any world implementation through a generated spec and yields after
# every tick, so differential and property tests share one harness.
module WorldDriver
  module_function

  def setup(world, spec)
    world.fertility = spec[:fert]
    world.fill_food(spec[:food])
    spec[:spawns].map { |s| world.spawn(*s) }
  end

  # Yields (tick, world, sensors, actions, births, deaths).
  def run(world, spec)
    rng = Random.new(spec[:actions_seed])
    out = Array.new(spec[:cap] * 6, 0)
    spec[:ticks].times do |t|
      world.sense(out)
      actions = Array.new(world.used) { rng.rand(-8..40) }
      births, deaths = world.act(actions, spec[:thresh])
      yield t, world, out.dup, actions, births, deaths if block_given?
      births.each { |i| world.spawn(10.0 + i, 20.0 + t, i, world.split(i), 1, 2) }
    end
    world
  end

  def digest(world) = Yarvpilled::StateDigest.world(world)
end
