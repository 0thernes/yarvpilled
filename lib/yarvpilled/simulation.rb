# frozen_string_literal: true

require_relative "genome"
require_relative "guardrails"
require_relative "experts"
require_relative "world"

module Yarvpilled
  # The living world. C (or pure Ruby) moves bodies; YARV runs minds.
  #
  # One tick:
  #   1. world.sense            -> sensor vector per creature
  #   2. Fiber attention        -> one Fiber per species, cooperatively
  #                                yielding every 8 creatures; each calls
  #                                its species' live `think` method (a
  #                                define_method'd ISeq) and clamps through
  #                                the Guardrails refinement
  #   3. world.act              -> movement, eating, collisions, deaths
  #   4. births                 -> split energy; mutate genome -> compile ->
  #                                to_binary -> load_from_binary -> new species
  #   5. periodic events        -> Ractor vote, TracePoint gene transfer,
  #                                GC.compact enlightenment, GC.start amnesia
  class Simulation
    using Guardrails

    WORLD_W = 768
    WORLD_H = 512
    FOOD_CELL = 8
    CAPACITY = 520
    POP_CAP = 480
    BIRTH_ENERGY = 720
    MUTATION_RATE = 0.3

    Species = Struct.new(:id, :parent_id, :gen, :genome, :mind, :born_tick, :extinct_tick, :alive,
                         :births, :fitness, :peak, :rewrites, :lane, :color, :instinct, :origin, keyword_init: true)

    attr_reader :world, :tick, :species, :events, :lineage, :stats, :votes, :rewrite_log, :world_impl,
                :max_gen, :births_total, :mutations_total, :rewrites_total, :compacts, :amnesias, :flash,
                :fiber_switches, :fiber_switches_total, :resurrections, :ractor_count, :gc_snapshot,
                :objects_snapshot, :yjit_snapshot, :last_compact, :apex_id, :sensors, :prof, :control

    # control: :selection (default) or :drift. Drift is the null model: the
    # brain still runs (same cost to the VM) but its output is replaced by a
    # random action, and metabolic cost is flat, so genomes carry no fitness
    # signal and evolve by mutation + random drift only.
    def initialize(seed: 42, world: (Native::AVAILABLE ? :native : :ruby), ractors: 6, log: nil, events_enabled: true,
                   control: :selection)
      @rng = Random.new(seed)
      @control = control
      raise ArgumentError, "control must be :selection or :drift" unless %i[selection drift].include?(control)

      @drift_rng = Random.new(seed ^ 0x5EED_D21F)
      @prof = Hash.new(0.0)
      @world_impl = world
      @world = World.build(world, WORLD_W, WORLD_H, FOOD_CELL, CAPACITY)
      @fw, @fh, = @world.food_dims
      @sensors = Array.new(CAPACITY * 6, 0)
      @actions = Array.new(CAPACITY, 0)
      @slot_species = Array.new(CAPACITY)
      @slot_gen = Array.new(CAPACITY, 0)
      @slot_alive = Array.new(CAPACITY, false)
      @species = {}
      @next_sid = 0
      @tick = 0
      @events = []
      @event_seq = 0
      @rewrite_log = []
      @votes = Hash.new { |h, k| h[k] = [] }
      @seed_bank = []
      @max_gen = 0
      @births_total = @mutations_total = @rewrites_total = 0
      @compacts = @amnesias = @resurrections = 0
      @fiber_switches = @fiber_switches_total = 0
      @flash = 0.0
      @log = log
      @events_enabled = events_enabled
      @ractor_count = events_enabled ? ractors : 0
      @experts = @ractor_count.positive? ? Experts.spawn_all(@ractor_count) : []
      @dream_pool = []
      @pending_rewrite = nil
      @think_calls = 0
      @gc_snapshot = GC.stat
      @objects_snapshot = ObjectSpace.count_objects
      @yjit_snapshot = yjit_stats
      @last_compact = nil
      @apex_id = nil
      refresh_fertility
      @world.fill_food(36)
      populate
    end

    def close
      @experts.each do |r|
        r.send([:stop, nil])
      rescue Ractor::ClosedError
        nil
      end
      @experts = []
    end

    def alive_count = @slot_alive.count(true)
    def think_calls = @think_calls
    def apex = @species[@apex_id]
    def live_species = @species.values.select { |s| s.alive.positive? }

    # ------------------------------------------------------------- tick
    def step!
      @tick += 1
      @flash *= 0.86
      refresh_fertility if (@tick % 25).zero?
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @world.sense(@sensors)
      t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      attend!
      t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      births, deaths = @world.act(@actions, BIRTH_ENERGY)
      t3 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      deaths.each { |slot| bury(slot) }
      births.each { |slot| give_birth(slot) }
      t4 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @prof[:sense] += t1 - t0
      @prof[:brains] += t2 - t1
      @prof[:act] += t3 - t2
      @prof[:births] += t4 - t3
      resurrect! if alive_count < 14
      if @events_enabled
        hive_vote! if (@tick % 40).zero? && !@experts.empty?
        arm_gene_transfer! if (@tick % 150) == 90
        enlighten! if (@tick % 300) == 150
        amnesia! if (@tick % 420) == 400
      end
      # Apex = highest recent reproductive success (births, decaying ~1%/tick).
      live = live_species
      live.each { |s| s.fitness *= 0.99 }
      @apex_id = live.max_by { |s| [s.fitness, s.alive, -s.id] }&.id
      sample_vm! if (@tick % 3).zero? || @tick < 3
      self
    end

    # Fiber-scheduled attention: one Fiber per species group; a tiny
    # round-robin scheduler resumes them until every creature has thought.
    def attend!
      groups = Hash.new { |h, k| h[k] = [] }
      CAPACITY.times { |s| groups[@slot_species[s]] << s if @slot_alive[s] }
      sens = @sensors
      acts = @actions
      drift = @control == :drift ? @drift_rng : nil
      fibers = groups.map do |sid, slots|
        mind = @species[sid].mind
        Fiber.new do
          slots.each_with_index do |s, k|
            b = s * 6
            out = mind.think(sens[b], sens[b + 1], sens[b + 2], sens[b + 3], sens[b + 4], sens[b + 5])
            acts[s] = drift ? drift.rand(4) : out.to_action
            observe_rewrite(sid, s, out) if @pending_rewrite
            Fiber.yield if (k & 7) == 7
          end
          :done
        end
      end
      switches = 0
      until fibers.empty?
        fibers.reject! do |f|
          switches += 1
          f.resume
          !f.alive?
        end
      end
      @think_calls += groups.sum { |_, v| v.size }
      @fiber_switches = switches
      @fiber_switches_total += switches
    end

    # ------------------------------------------------------- population
    def populate
      root = register(Genome.seed, nil, origin: :seed)
      variants = [root] + Array.new(7) { register(root.genome.mutate(@rng, dreamer: @events_enabled ? dreamer : nil), root.id, origin: :mutation) }
      90.times do |i|
        sp = variants[i % variants.size]
        place(sp, @rng.rand * WORLD_W, @rng.rand * WORLD_H, 600 + @rng.rand(100), 0)
      end
    end

    def register(genome, parent_id, origin:)
      sid = @next_sid
      @next_sid += 1
      klass = Class.new(Mind)
      klass.define_method(:think, &genome.brain)
      parent = parent_id && @species[parent_id]
      lane = parent ? reflect(parent.lane + @rng.rand(-0.28..0.28)) : 0.5
      sp = Species.new(id: sid, parent_id: parent_id, gen: parent ? parent.gen + 1 : 0, genome: genome,
                       mind: klass.new(sid), born_tick: @tick, extinct_tick: nil, alive: 0, births: 0, fitness: 0.0, peak: 0,
                       rewrites: 0, lane: lane, color: genome.color, instinct: false, origin: origin)
      @species[sid] = sp
      remember_ops(genome)
      sp
    end

    def reflect(v)
      v = 0.1 - v if v < 0.05
      v = 1.74 - v if v > 0.87
      v.clamp(0.05, 0.87)
    end

    def place(sp, x, y, energy, gen)
      slot = @world.spawn(x, y, @rng.rand(64), energy, sp.id, cost_of(sp.genome))
      return nil unless slot

      @slot_species[slot] = sp.id
      @slot_gen[slot] = gen
      @slot_alive[slot] = true
      sp.alive += 1
      sp.peak = sp.alive if sp.alive > sp.peak
      slot
    end

    def cost_of(genome) = @control == :drift ? 2 : genome.traits[:cost]

    def bury(slot)
      @slot_alive[slot] = false
      sp = @species[@slot_species[slot]]
      sp.alive -= 1
      if sp.alive.zero?
        extinct!(sp)
      elsif sp.alive <= 3 && sp.peak >= 12 && !sp.instinct && @events_enabled
        sp.mind.singleton_class.prepend(Instinct)
        sp.instinct = true
        event(:prepend, "species ##{sp.id} collapsing -> singleton_class.prepend(Instinct): #{sp.mind.singleton_class.ancestors.first(2).map { _1.to_s[0, 22] }.join(' < ')}", sp.color)
      end
    end

    def extinct!(sp)
      sp.extinct_tick = @tick
      if sp.peak >= 8
        @seed_bank << [sp.peak, sp.id, sp.genome.binary, sp.genome]
        @seed_bank = @seed_bank.max_by(16) { _1[0] }
      end
      # Amnesia for real: drop the only references to the mind and brain so
      # the next GC can reclaim the class, lambda and ISeq.
      sp.mind = nil
      sp.genome = nil unless @seed_bank.any? { _1[1] == sp.id }
    end

    def give_birth(slot)
      return if alive_count >= POP_CAP

      parent = @species[@slot_species[slot]]
      energy = @world.split(slot)
      return if energy <= 0

      sp =
        if @rng.rand < MUTATION_RATE
          @mutations_total += 1
          g = parent.genome.mutate(@rng, dreamer: @events_enabled ? dreamer : nil)
          event(:dream, "dreamed constant from heap: #{g.dream}", parent.color) if g.dream && @rng.rand < 0.3
          register(g, parent.id, origin: :mutation)
        else
          parent
        end
      snap_x, snap_y = slot_pos(slot)
      gen = @slot_gen[slot] + 1
      child = place(sp, snap_x + @rng.rand(-6.0..6.0), snap_y + @rng.rand(-6.0..6.0), energy, gen)
      return unless child

      @births_total += 1
      parent.births += 1
      parent.fitness += 1.0
      @max_gen = gen if gen > @max_gen
    end

    # Re-seed from the gene bank using ONLY the serialized bytecode:
    # RubyVM::InstructionSequence.load_from_binary(bin).eval -> brain.
    def resurrect!
      entry = @seed_bank.max_by { _1[0] }
      if entry
        _peak, old_id, bin, genome = entry
        brain = Genome.brain_from_binary(bin)
        sp = register(genome, old_id, origin: :resurrected)
        sp.mind.class.define_method(:think, &brain)
        event(:resurrect, "extinction pressure: load_from_binary(#{bin.bytesize}B) resurrects lineage of ##{old_id} as ##{sp.id}", sp.color)
      else
        sp = register(Genome.seed, nil, origin: :seed)
      end
      @resurrections += 1
      24.times { place(sp, @rng.rand * WORLD_W, @rng.rand * WORLD_H, 420, @max_gen / 2) }
    end

    # Positions come from one snapshot per tick (cached), not per birth.
    def slot_pos(slot)
      if @pos_tick != @tick
        @pos_tick = @tick
        @pos = {}
        snap = @world.snapshot
        (0...snap.size).step(8) { |i| @pos[snap[i]] = [snap[i + 1], snap[i + 2]] }
      end
      @pos[slot] || [@rng.rand * WORLD_W, @rng.rand * WORLD_H]
    end

    # ----------------------------------------------------------- events
    def hive_vote!
      cands = live_species.max_by(12) { |s| s.alive }.map do |s|
        [s.id, s.genome.histogram.transform_keys(&:to_s), s.genome.bytecode_len, s.alive, s.births]
      end
      return if cands.empty?

      msg = Ractor.make_shareable([@tick, cands])
      @experts.each { |r| r.send(msg) }
      results = @experts.map(&:take)
      tally = Hash.new(0)
      results.each do |name, _epoch, sid, score, dt, rid|
        tally[sid] += 1 if sid
        sp = @species[sid]
        @votes[name] << { tick: @tick, sid: sid, score: score, ns: dt, color: sp&.color || [90, 90, 90], ractor: rid }
        @votes[name].shift while @votes[name].size > 40
      end
      winner_id, n = tally.max_by { |sid, c| [c, -sid] }
      winner = @species[winner_id]
      return unless winner && winner.alive.positive?

      CAPACITY.times { |s| @world.feed(s, 90) if @slot_alive[s] && @slot_species[s] == winner_id }
      event(:vote, "Ractor hive-mind (#{@experts.size} isolates) blesses ##{winner_id} with #{n}/#{@experts.size} votes", winner.color)
    end

    # Horizontal gene transfer through TracePoint: arm a targeted :call hook
    # on the weakest living species' think method. When YARV next enters
    # that method, the hook fires mid-call, inspects caller_locations, and
    # redefines the method with a mutated copy of the apex genome. The
    # in-flight call finishes on the OLD bytecode; the next call runs the NEW.
    def arm_gene_transfer!
      return if @pending_rewrite

      ap = apex
      weak = live_species.reject { _1.id == @apex_id || _1.mind.nil? }.min_by { |s| [s.fitness, s.alive, s.id] }
      return unless ap && weak

      donor = ap.genome.mutate(@rng)
      target = weak.mind.class.instance_method(:think)
      before = RubyVM::InstructionSequence.of(target)
      rec = { tick: @tick, species: weak.id, donor: ap.id, before_disasm: before.disasm, before_len: weak.genome.bytecode_len,
              before_source: weak.genome.source }
      tp = TracePoint.new(:call) do |t|
        t.disable
        rec[:fired_tick] = @tick
        rec[:method] = t.method_id
        rec[:stack] = caller_locations(1, 6).map { |l| "#{File.basename(l.path.to_s)}:#{l.lineno}:#{l.label}" }
        klass = weak.mind.class
        klass.send(:remove_method, :think) if klass.method_defined?(:think, false) # explicit swap: no -w redefinition warning
        klass.define_method(:think, &donor.brain)
        rec[:after_disasm] = RubyVM::InstructionSequence.of(weak.mind.class.instance_method(:think)).disasm
        rec[:stage] = :rewritten
      end
      rec[:tp] = tp
      rec[:weak_ref] = weak
      rec[:donor_genome] = donor
      @pending_rewrite = rec
      tp.enable(target: target)
    end

    def observe_rewrite(sid, slot, out)
      rec = @pending_rewrite
      return unless rec[:species] == sid

      case rec[:stage]
      when :rewritten
        rec[:inflight_result] = out
        rec[:stage] = :awaiting_next
      when :awaiting_next
        rec[:next_result] = out
        b = slot * 6
        rec[:inputs] = @sensors[b, 6]
        finish_rewrite(rec)
      end
    end

    def finish_rewrite(rec)
      weak = rec.delete(:weak_ref)
      donor = rec.delete(:donor_genome)
      rec.delete(:tp)
      weak.genome = donor
      weak.color = donor.color
      weak.rewrites += 1
      cost = cost_of(donor)
      CAPACITY.times { |s| @world.set_species(s, weak.id, cost) if @slot_alive[s] && @slot_species[s] == weak.id }
      remember_ops(donor)
      @rewrites_total += 1
      rec[:after_len] = donor.bytecode_len
      rec[:after_source] = donor.source
      @rewrite_log << rec
      @pending_rewrite = nil
      @flash = [@flash, 0.6].max
      event(:rewrite, "TracePoint(:call) rewrote ##{weak.id}#think mid-call: #{rec[:before_len]}w -> #{rec[:after_len]}w, in-flight=#{rec[:inflight_result]} next=#{rec[:next_result]}", donor.color)
      write_rewrite_log(rec)
    end

    def enlighten!
      before = GC.stat(:heap_live_slots)
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      GC.compact
      ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round(1)
      info = GC.latest_compact_info
      moved = info[:moved].values.sum
      considered = info[:considered].values.sum
      @compacts += 1
      @flash = 1.0
      @last_compact = { tick: @tick, moved: moved, considered: considered, ms: ms, live_before: before,
                        top: info[:moved].max_by(3) { _2 }.map { |k, v| "#{k.to_s.sub('T_', '')}:#{v}" } }
      event(:compact, "ENLIGHTENMENT: GC.compact moved #{moved}/#{considered} objects in #{ms}ms", [255, 255, 255])
    end

    def amnesia!
      before = GC.stat(:heap_live_slots)
      GC.start(full_mark: true, immediate_sweep: true)
      after = GC.stat(:heap_live_slots)
      @amnesias += 1
      @flash = [@flash, 0.45].max
      event(:amnesia, "AMNESIA: GC.start(full_mark: true) forgot #{before - after} heap slots (extinct minds reclaimed)", [255, 80, 200])
    end

    # ObjectSpace "hallucination": mutation constants sampled from live
    # classes on the heap (name length + method count), labelled by class.
    def dreamer
      @dreamer ||= lambda do
        if @dream_pool.empty? || (@tick % 100).zero?
          @dream_pool = ObjectSpace.each_object(Class).select(&:name).first(400)
        end
        c = @dream_pool.sample(random: @rng)
        val = (c.name.size + c.instance_methods(false).size) % 64
        [val, "#{c.name}=>#{val}"]
      end
    end

    # -------------------------------------------------------- telemetry
    def sample_vm!
      @gc_snapshot = GC.stat
      @objects_snapshot = ObjectSpace.count_objects if (@tick % 6).zero? || @tick < 3
      @yjit_snapshot = yjit_stats
    end

    def yjit_stats
      return nil unless defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?

      s = RubyVM::YJIT.runtime_stats
      { compiled_iseqs: s[:compiled_iseq_count], compiled_blocks: s[:compiled_block_count],
        inline_code: s[:inline_code_size], outlined_code: s[:outlined_code_size],
        invalidations: s[:invalidation_count] }.compact
    end

    def recent_ops = @recent_ops ||= []

    def remember_ops(genome)
      ops = Genome.instructions(genome.iseq).map { _1[0].to_s }
      recent_ops.concat(ops.sample(10, random: @rng))
      recent_ops.shift(recent_ops.size - 400) if recent_ops.size > 400
    end

    def event(kind, text, color)
      @event_seq += 1
      e = { seq: @event_seq, tick: @tick, kind: kind, text: text, color: color }
      @events << e
      @events.shift while @events.size > 30
      @log&.puts("[t=#{@tick.to_s.rjust(5)}] #{kind.to_s.upcase.ljust(9)} #{text}")
    end

    def write_rewrite_log(rec)
      return unless @log

      @log.puts "=" * 78
      @log.puts "SELF-REWRITE at tick #{rec[:tick]} (fired t=#{rec[:fired_tick]}): species ##{rec[:species]} <- apex ##{rec[:donor]}"
      @log.puts "TracePoint(:call) target method: #{rec[:method]}   caller_locations inside hook:"
      rec[:stack].each { |l| @log.puts "    #{l}" }
      @log.puts "in-flight call (old bytecode) returned: #{rec[:inflight_result]}"
      @log.puts "next call (new bytecode) returned:      #{rec[:next_result]}   inputs=#{rec[:inputs].inspect}"
      @log.puts "--- BEFORE source ---", rec[:before_source]
      @log.puts "--- BEFORE disasm (#{rec[:before_len]} words) ---", rec[:before_disasm]
      @log.puts "--- AFTER source ---", rec[:after_source]
      @log.puts "--- AFTER disasm (#{rec[:after_len]} words) ---", rec[:after_disasm]
      @log.puts "=" * 78
      @log.flush
    end

    def refresh_fertility
      @fertility_bytes = Simulation.fertility_bytes(@tick, @fw, @fh)
      @world.fertility = @fertility_bytes
    end

    # Five drifting Gaussian food patches; deterministic in (tick, fw, fh).
    def self.fertility_bytes(tick, fw, fh)
      t = tick / 25.0
      patches = Array.new(5) do |k|
        a = t * (0.05 + k * 0.013) + k * 1.7
        [(fw / 2.0) + Math.cos(a) * fw * (0.18 + 0.06 * k), (fh / 2.0) + Math.sin(a * 1.3) * fh * (0.16 + 0.05 * k), 7.0 + k * 1.5]
      end
      bytes = Array.new(fw * fh)
      fh.times do |y|
        fw.times do |x|
          v = 1.0
          patches.each do |px, py, r|
            dx = (x - px).abs
            dx = fw - dx if dx > fw / 2
            dy = (y - py).abs
            dy = fh - dy if dy > fh / 2
            v += 52.0 * Math.exp(-(dx * dx + dy * dy) / (2 * r * r))
          end
          bytes[y * fw + x] = v > 255 ? 255 : v.to_i
        end
      end
      bytes.pack("C*")
    end

    attr_reader :fertility_bytes, :slot_species, :slot_alive, :slot_gen
  end
end
