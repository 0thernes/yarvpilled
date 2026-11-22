# frozen_string_literal: true

require "json"

module Yarvpilled
  # Serializes live Simulation state into plain JSON-able hashes for the
  # browser (SSE) and for tests. Nothing here is synthesized: it's a view.
  module Telemetry
    module_function

    def frame(sim, full: false)
      snap = sim.world.snapshot
      creatures = []
      (0...snap.size).step(8) do |i|
        creatures << [snap[i + 1].round(1), snap[i + 2].round(1), snap[i + 3], snap[i + 5], snap[i + 4], snap[i + 7]]
      end
      live = sim.live_species
      out = {
        t: sim.tick, gen: sim.max_gen, pop: sim.alive_count, species_alive: live.size,
        births: sim.births_total, mutations: sim.mutations_total, rewrites: sim.rewrites_total,
        compacts: sim.compacts, amnesias: sim.amnesias, flash: sim.flash.round(3),
        world: { w: Simulation::WORLD_W, h: Simulation::WORLD_H, impl: sim.world_impl },
        ruby: RUBY_VERSION, yjit: !sim.yjit_snapshot.nil?,
        creatures: creatures,
        species: live.to_h { |sp| [sp.id, species_json(sp)] },
        apex: apex_json(sim),
        opcodes: population_opcodes(sim),
        gc: sim.gc_snapshot.slice(:count, :minor_gc_count, :major_gc_count, :heap_live_slots, :heap_free_slots,
                                  :heap_available_slots, :total_allocated_objects, :total_freed_objects, :compact_count),
        objects: sim.objects_snapshot.slice(:TOTAL, :FREE, :T_OBJECT, :T_CLASS, :T_STRING, :T_ARRAY, :T_HASH, :T_DATA, :T_IMEMO),
        yjit_stats: sim.yjit_snapshot,
        fibers: { switches: sim.fiber_switches, total: sim.fiber_switches_total }, think_calls: sim.think_calls,
        votes: sim.votes.transform_values { |vs| vs.last(17).map { |v| [v[:sid], v[:color], v[:ns]] } },
        ractors: sim.ractor_count,
        events: sim.events.last(8).map { |e| e.merge(kind: e[:kind].to_s) },
        last_compact: sim.last_compact,
        last_rewrite: (rw = sim.rewrite_log.last) && { species: rw[:species], fired: rw[:fired_tick], before: rw[:before_len], after: rw[:after_len] },
        ops: sim.recent_ops.last(12)
      }
      if full || (sim.tick % 3).zero?
        fw, fh, cell = sim.world.food_dims
        out[:food] = { w: fw, h: fh, cell: cell, b64: [sim.world.food_bytes].pack("m0") }
      end
      out[:lineage] = lineage(sim) if full || (sim.tick % 10).zero?
      out
    end

    def species_json(sp)
      tr = sp.genome.traits
      { c: sp.color, r: tr[:radius], s: tr[:sides], tr: tr[:trail], n: sp.alive, gen: sp.gen,
        len: sp.genome.bytecode_len, inst: sp.instinct, born: sp.born_tick, origin: sp.origin }
    end

    def apex_json(sim)
      ap = sim.apex
      return nil unless ap&.mind

      m = ap.mind.class.instance_method(:think)
      { id: ap.id, gen: ap.gen, alive: ap.alive, len: ap.genome.bytecode_len, bin: ap.genome.binary.bytesize,
        cost: ap.genome.traits[:cost], source: ap.genome.source,
        disasm: RubyVM::InstructionSequence.of(m).disasm.lines.map(&:rstrip).first(60) }
    end

    def population_opcodes(sim)
      agg = Hash.new(0)
      sim.live_species.each { |sp| sp.genome.histogram.each { |k, v| agg[k] += v * sp.alive } }
      agg.sort_by { |k, v| [-v, k] }.first(10).map { |k, v| [k.to_s, v] }
    end

    def lineage(sim)
      sim.species.values.last(500).map do |sp|
        [sp.id, sp.parent_id, sp.born_tick, sp.lane.round(3), sp.color, sp.alive, sp.extinct_tick]
      end
    end

    def to_json(sim, full: false) = JSON.generate(frame(sim, full: full))
  end
end
