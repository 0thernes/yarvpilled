# frozen_string_literal: true

require_relative "gfx"

module Yarvpilled
  # Draws one 1280x720 frame from live Simulation state. Every number, color
  # and glyph comes from the running VM: creature bodies from their real
  # opcode histograms, the rain from opcodes of freshly compiled genomes,
  # the disasm panel from RubyVM::InstructionSequence.of(apex#think), gauges
  # from GC.stat / ObjectSpace.count_objects / RubyVM::YJIT.runtime_stats.
  class Renderer
    W = 1280
    H = 720
    WX = 12
    WY = 56
    CYAN = [0, 235, 255].freeze
    MAGENTA = [255, 46, 196].freeze
    LIME = [120, 255, 140].freeze
    AMBER = [255, 186, 48].freeze
    VIOLET = [166, 104, 255].freeze
    WHITE = [235, 245, 255].freeze
    DIM = [90, 110, 150].freeze
    ACTIONS = %w[GRAZE LEFT RIGHT DASH].freeze

    attr_reader :canvas

    def initialize(sim)
      @sim = sim
      @canvas = Canvas.new(W, H)
      @trail = Canvas.new(Simulation::WORLD_W, Simulation::WORLD_H)
      @frame = 0
      @pop_hist = []
      @sp_hist = []
      @rng = Random.new(99)
      @rain = Array.new(30) { |i| new_drop(i, true) }
      @palette = build_palette
      @disasm_cache = {}
      @ruby_label = "ruby #{RUBY_VERSION} #{yjit? ? '+YJIT' : '(interp)'}"
    end

    def yjit? = defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?

    def render
      @frame += 1
      s = @sim
      @pop_hist << s.alive_count
      @sp_hist << s.live_species.size
      @pop_hist.shift while @pop_hist.size > 380
      @sp_hist.shift while @sp_hist.size > 380
      c = @canvas
      c.fill([4, 5, 12])
      backdrop
      header
      world
      disasm_panel
      opcode_panel
      vm_panel
      ractor_panel
      lineage_panel
      events_panel
      flash_overlay
      c.scanlines(28)
      c
    end

    private

    def build_palette
      (0..255).map do |v|
        t = (v / 255.0)**0.8
        [(t * 30).to_i, (t * 120 + t * t * 40).to_i, (t * 110).to_i].pack("C3")
      end.join.b
    end

    def backdrop
      c = @canvas
      (0...W).step(40) { |x| c.rect(x, 0, 1, H, [20, 30, 70], 40) }
      (0...H).step(40) { |y| c.rect(0, y, W, 1, [20, 30, 70], 40) }
    end

    # ----------------------------------------------------------- header
    def header
      c = @canvas
      s = @sim
      c.rect(0, 0, W, 46, [8, 6, 22], 255)
      W.times { |x| c.rect(x, 45, 1, 2, Genome.hsv((x * 0.35 + @frame * 2) % 360, 0.9, 1.0), 220) }
      c.text("YARVPILLED", 15, 13, MAGENTA, 200, font: :large)
      c.text("YARVPILLED", 13, 11, CYAN, 200, font: :large)
      x = c.text("YARVPILLED", 14, 12, WHITE, 255, font: :large)
      c.text(" // pure ISeq cognition // zero models", x + 4, 14, [150, 210, 255], 255, font: :bold)
      world_label = s.world_impl == :native ? "world: C ext (ruby.h)" : "world: pure Ruby"
      right1 = "#{@ruby_label} | #{world_label} | #{Simulation::WORLD_W}x#{Simulation::WORLD_H} A-Life"
      right2 = format("t=%05d  gen %-3d pop %-4d species %-4d births %-5d rewrites %-3d compacts %d",
                      s.tick, s.max_gen, s.alive_count, s.live_species.size, s.births_total, s.rewrites_total, s.compacts)
      c.text(right1, W - 12 - c.text_width(right1), 7, [120, 160, 220])
      c.text(right2, W - 12 - c.text_width(right2), 25, AMBER)
    end

    # ------------------------------------------------------------ world
    def world
      c = @canvas
      s = @sim
      ww = Simulation::WORLD_W
      wh = Simulation::WORLD_H
      c.panel(WX - 4, WY - 4, ww + 8, wh + 8, "WORLD // every creature's brain is a live YARV ISeq", CYAN)
      c.rect(WX, WY, ww, wh, [2, 4, 10], 255)
      fw, fh, cell = s.world.food_dims
      c.heat(s.world.food_bytes, fw, fh, cell, WX, WY, @palette)
      (0...ww).step(32) { |x| c.rect(WX + x, WY, 1, wh, [30, 60, 120], 28) }
      (0...wh).step(32) { |y| c.rect(WX, WY + y, ww, 1, [30, 60, 120], 28) }
      rain

      snap = s.world.snapshot
      @trail.scale(0, 0, ww, wh, 214)
      by_species = Hash.new { |h, k| h[k] = [] }
      i = 0
      while i < snap.size
        sid = snap[i + 5]
        sp = s.species[sid]
        if sp&.genome
          tr = sp.genome.traits
          @trail.glow(snap[i + 1], snap[i + 2], tr[:radius] * 1.5, sp.color, 40 + tr[:trail] * 6)
          by_species[sid] << i
        end
        i += 8
      end
      c.blit_add(@trail, WX, WY)

      i = 0
      while i < snap.size
        sp = s.species[snap[i + 5]]
        if sp&.genome
          x = WX + snap[i + 1]
          y = WY + snap[i + 2]
          tr = sp.genome.traits
          rad = tr[:radius]
          ang = snap[i + 3] * Math::PI / 32
          col = sp.color
          c.glow(x, y, rad * 2.6, col, 70)
          c.ngon(x, y, rad, tr[:sides], ang + (sp.id % 7) * 0.3, col, 235)
          c.disc(x, y, rad * 0.42, [8, 8, 20], 220)
          c.disc(x, y, 1.3, WHITE, 255)
          c.line(x, y, x + Math.cos(ang) * rad * 1.7, y + Math.sin(ang) * rad * 1.7, WHITE, 170, add: true)
          c.ring(x, y, rad + 2.5, 1.0, sp.instinct ? AMBER : col, 120) if sp.instinct || sp.id == s.apex_id
        end
        i += 8
      end

      # Speciation bursts: species born in the last 24 ticks.
      by_species.each do |sid, idxs|
        sp = s.species[sid]
        age = s.tick - sp.born_tick
        next unless age < 24 && sp.origin != :seed

        j = idxs.first
        x = WX + snap[j + 1]
        y = WY + snap[j + 2]
        c.ring(x, y, 6 + age * 1.6, 1.5, sp.color, 220 - age * 9)
        c.text("+##{sid}", x + 8, y - 16, sp.color, 230 - age * 9)
      end

      # TracePoint rewrite shockwave on all members of the rewritten species.
      if (rw = s.rewrite_log.last) && (age = s.tick - rw[:fired_tick].to_i) < 40
        (by_species[rw[:species]] || []).each do |j|
          c.ring(WX + snap[j + 1], WY + snap[j + 2], 8 + age * 0.9, 2, MAGENTA, 240 - age * 6)
        end
        c.text("TracePoint(:call) -> define_method  ##{rw[:species]}#think REWRITTEN MID-CALL", WX + 12, WY + wh - 40, MAGENTA, 255 - age * 5, font: :bold)
      end

      apex_reticle(snap, by_species)
      legend
    end

    def apex_reticle(snap, by_species)
      s = @sim
      ap = s.apex
      return unless ap && (idxs = by_species[ap.id]) && !idxs.empty?

      j = idxs.max_by { |k| snap[k + 4] }
      c = @canvas
      x = WX + snap[j + 1]
      y = WY + snap[j + 2]
      r = 15 + Math.sin(@frame * 0.25) * 2
      c.ring(x, y, r, 1.5, MAGENTA, 230)
      4.times do |k|
        a = k * Math::PI / 2 + @frame * 0.05
        c.line(x + Math.cos(a) * (r + 3), y + Math.sin(a) * (r + 3), x + Math.cos(a) * (r + 10), y + Math.sin(a) * (r + 10), MAGENTA, 255)
      end
      label = "APEX ##{ap.id} gen#{s.slot_gen[snap[j]]} E=#{snap[j + 4]} #{ACTIONS[snap[j + 7]]}"
      lx = (x + 22).clamp(WX, WX + Simulation::WORLD_W - c.text_width(label) - 8)
      ly = (y - 26).clamp(WY + 4, WY + Simulation::WORLD_H - 20)
      c.rect(lx - 4, ly - 2, c.text_width(label) + 8, 16, [10, 4, 20], 200)
      c.rect(lx - 4, ly - 2, 2, 16, MAGENTA, 255)
      c.text(label, lx, ly, WHITE)
      c.line(x + r * 0.7, y - r * 0.7, lx - 4, ly + 6, MAGENTA, 160)
    end

    def legend
      c = @canvas
      y = WY + Simulation::WORLD_H - 18
      c.rect(WX + 6, y - 3, 560, 17, [2, 4, 10], 170)
      c.text("body: hue=opcode mix  size=sqrt(bytecode)  sides=distinct opcodes  glow=branches", WX + 12, y, [130, 170, 210])
    end

    def new_drop(i, scatter)
      ops = @sim.recent_ops
      word = ops.empty? ? "leave" : ops.sample(random: @rng)
      { x: (i * 26 + 8) % Simulation::WORLD_W, y: scatter ? @rng.rand(Simulation::WORLD_H) : -@rng.rand(200),
        v: 1.5 + @rng.rand * 3.5, word: word }
    end

    def rain
      c = @canvas
      @rain.each_with_index do |d, i|
        d[:y] += d[:v]
        @rain[i] = d = new_drop(i, false) if d[:y] > Simulation::WORLD_H + 20
        d[:word].each_char.with_index do |ch, k|
          yy = d[:y] - k * 12
          next if yy < -10 || yy > Simulation::WORLD_H - 12

          a = k.zero? ? 190 : (130 - k * 7).clamp(25, 130)
          c.text(ch, WX + d[:x], WY + yy, k.zero? ? [200, 255, 230] : [40, 200, 150], a)
        end
      end
    end

    # ---------------------------------------------------------- disasm
    def disasm_panel
      c = @canvas
      s = @sim
      x = 792
      y = 60
      pw = 476
      ph = 236
      ap = s.apex
      c.panel(x, y, pw, ph, "APEX MIND // ISeq.of(species_#{ap&.id}.think).disasm", MAGENTA)
      return unless ap&.mind

      key = [ap.id, ap.rewrites, ap.instinct]
      lines = (@disasm_cache[key] ||= begin
        m = ap.mind.class.instance_method(:think)
        RubyVM::InstructionSequence.of(m).disasm.lines.map(&:rstrip)
      end)
      @disasm_cache.shift while @disasm_cache.size > 32
      g = ap.genome
      info = "#{g.bytecode_len} words | to_binary #{g.binary.bytesize}B | cost #{g.traits[:cost]}/tick | pop #{ap.alive} | gen #{ap.gen}"
      c.text(info, x + 10, y + 12, AMBER)
      visible = 16
      body = lines.drop(3)
      head = lines.first(1)
      c.text(head.first.to_s[0, 76], x + 10, y + 28, [120, 140, 190])
      off = body.size > visible ? (@frame / 5) % (body.size - visible + 6) : 0
      off = [off, [body.size - visible, 0].max].min
      pc = body.empty? ? 0 : (@frame / 3) % body.size
      body[off, visible].to_a.each_with_index do |ln, k|
        ly = y + 44 + k * 12
        idx = off + k
        c.rect(x + 6, ly - 1, pw - 12, 13, MAGENTA, 60) if idx == pc
        if (m = ln.match(/\A(\d{4}) (\S+)\s*(.*)\z/))
          xx = c.text(m[1], x + 10, ly, [90, 100, 140])
          xx = c.text(" #{m[2].ljust(20)}", xx, ly, m[2].start_with?("branch", "jump") ? AMBER : CYAN)
          c.text(m[3].gsub(/\s+/, " ")[0, 44], xx, ly, [200, 210, 230])
        else
          c.text(ln[0, 76], x + 10, ly, [150, 160, 200])
        end
      end
    end

    # --------------------------------------------------------- opcodes
    def opcode_panel
      c = @canvas
      s = @sim
      x = 792
      y = 308
      pw = 476
      ph = 136
      c.panel(x, y, pw, ph, "POPULATION OPCODE HISTOGRAM // iseq.to_a", CYAN)
      agg = Hash.new(0)
      s.live_species.each { |sp| sp.genome&.histogram&.each { |k, v| agg[k] += v * sp.alive } }
      top = agg.sort_by { |k, v| [-v, k] }.first(9)
      max = top.first&.last.to_f
      total = agg.values.sum
      c.text("#{total} live instructions across #{s.alive_count} brains", x + 10, y + 12, [130, 160, 210])
      top.each_with_index do |(op, n), k|
        ly = y + 28 + k * 11.6
        c.text(op.to_s[0, 22], x + 10, ly.to_i, [190, 200, 230])
        bw = max.positive? ? ((pw - 220) * n / max).to_i : 0
        col = Genome.hsv((190 + k * 22 + @frame) % 360, 0.85, 1.0)
        c.rect(x + 150, ly.to_i + 2, bw, 8, col, 220)
        c.glow(x + 150 + bw, ly + 6, 9, col, 120)
        c.text(n.to_s, x + 156 + bw, ly.to_i, col)
      end
    end

    # -------------------------------------------------------------- vm
    def vm_panel
      c = @canvas
      s = @sim
      x = 792
      y = 456
      pw = 476
      ph = 108
      c.panel(x, y, pw, ph, "VM // GC.stat  ObjectSpace  YJIT", LIME)
      g = s.gc_snapshot
      live = g[:heap_live_slots].to_f
      avail = g[:heap_available_slots].to_f
      o = s.objects_snapshot
      imemo = o[:T_IMEMO].to_f
      tot = o[:TOTAL].to_f
      gauges = [
        ["HEAP", live / avail, CYAN, "#{(live / 1000).round}k"],
        ["IMEMO", imemo / (tot - o[:FREE].to_f), VIOLET, "#{(imemo / 1000).round(1)}k"],
        if (y2 = s.yjit_snapshot)
          ["YJIT", [y2[:inline_code].to_f / 16_000_000, 1].min, AMBER, "#{(y2[:inline_code].to_f / 1024).round}KB"]
        else
          ["MAJOR", g[:major_gc_count].to_f / [g[:count], 1].max, AMBER, "#{g[:major_gc_count]}/#{g[:count]}"]
        end
      ]
      gauges.each_with_index do |(name, frac, col, val), k|
        cx = x + 44 + k * 78
        cy = y + 58
        c.ring(cx, cy, 28, 6, [30, 40, 60], 255)
        c.arc(cx, cy, 28, 6, -Math::PI / 2, -Math::PI / 2 + 2 * Math::PI * frac.clamp(0, 1), col, 255)
        c.glow(cx, cy, 22, col, (40 + s.flash * 200).to_i)
        c.text(val, cx - c.text_width(val) / 2, cy - 6, WHITE)
        c.text(name, cx - c.text_width(name) / 2, cy + 36, col)
      end
      tx = x + 248
      lc = s.last_compact
      rows = [
        ["GC.count", "#{g[:count]} (minor #{g[:minor_gc_count]} major #{g[:major_gc_count]})"],
        ["compact", "#{g[:compact_count] || s.compacts} moved #{lc ? lc[:moved] : '-'}"],
        ["live/free", "#{g[:heap_live_slots]} / #{g[:heap_free_slots]}"],
        ["T_CLASS", "#{o[:T_CLASS]}  T_DATA #{o[:T_DATA]}"],
        ["fibers", "#{s.fiber_switches} switch/tick"],
        ["think()", "#{s.think_calls} YARV calls"],
        ["ractors", "#{s.ractor_count} isolates  amnesia x#{s.amnesias}"]
      ]
      rows.each_with_index do |(k, v), i|
        c.text(k, tx, y + 12 + i * 13, LIME)
        c.text(v[0, 27], tx + 62, y + 12 + i * 13, [200, 215, 235])
      end
    end

    # ---------------------------------------------------------- ractors
    def ractor_panel
      c = @canvas
      s = @sim
      x = 8
      y = 584
      pw = 384
      ph = 128
      c.panel(x, y, pw, ph, "RACTOR HIVE-MIND // parallel expert votes", VIOLET)
      Experts::ROSTER.first(s.ractor_count).each_with_index do |(name, _), k|
        ly = y + 12 + k * 19
        col = Genome.hsv(260 + k * 18, 0.6, 1.0)
        c.text(name, x + 10, ly, col)
        votes = s.votes[name].last(17)
        votes.each_with_index do |v, j|
          vx = x + 116 + j * 11
          c.rect(vx, ly + 1, 9, 10, v[:color], 230)
          c.glow(vx + 4, ly + 6, 8, v[:color], 60) if j == votes.size - 1
        end
        if (last = votes.last)
          c.text("##{last[:sid]} #{(last[:ns] / 1000.0).round(1)}us", x + 306, ly, [190, 200, 230])
        end
      end
    end

    # ---------------------------------------------------------- lineage
    def lineage_panel
      c = @canvas
      s = @sim
      x = 400
      y = 584
      pw = 404
      ph = 128
      c.panel(x, y, pw, ph, "LINEAGE // species tree + population", AMBER)
      span = [s.tick, 600].max.to_f
      ix = x + 10
      iw = pw - 20
      iy = y + 12
      ih = ph - 22
      pos = ->(sp) { [ix + iw * sp.born_tick / span, iy + ih * sp.lane] }
      list = s.species.values.last(500)
      list.each do |sp|
        par = sp.parent_id && s.species[sp.parent_id]
        next unless par

        x0, y0 = pos.call(par)
        x1, y1 = pos.call(sp)
        alive = sp.alive.positive?
        c.line(x0, y0, x1, y0, sp.color, alive ? 120 : 30)
        c.line(x1, y0, x1, y1, sp.color, alive ? 160 : 40)
      end
      list.each do |sp|
        next unless sp.alive.positive?

        x1, y1 = pos.call(sp)
        ex = ix + iw * s.tick / span
        c.line(x1, y1, ex, y1, sp.color, 90)
        c.disc(ex, y1, 1.5 + Math.sqrt(sp.alive) * 0.5, sp.color, 255)
      end
      # population + species sparklines
      [[@pop_hist, AMBER, Simulation::POP_CAP], [@sp_hist, MAGENTA, [@sp_hist.max.to_i, 1].max]].each do |hist, col, mx|
        next if hist.size < 2

        hist.each_cons(2).with_index do |(a, b), k|
          xa = ix + iw * k / 380.0
          xb = ix + iw * (k + 1) / 380.0
          c.line(xa, iy + ih - ih * 0.45 * a / mx, xb, iy + ih - ih * 0.45 * b / mx, col, 140, add: true)
        end
      end
      c.text("pop", ix, iy + ih - 12, AMBER, 200)
      c.text("species", ix + 30, iy + ih - 12, MAGENTA, 200)
    end

    # ----------------------------------------------------------- events
    def events_panel
      c = @canvas
      s = @sim
      x = 812
      y = 584
      pw = 460
      ph = 128
      c.panel(x, y, pw, ph, "EVENT STREAM // real VM events", MAGENTA)
      s.events.last(8).reverse.each_with_index do |e, k|
        ly = y + 12 + k * 14
        a = 255 - k * 18
        c.disc(x + 14, ly + 6, 3, e[:color], a)
        xx = c.text(format("t%05d", e[:tick]), x + 22, ly, [110, 120, 160], a)
        c.text(e[:text][0, 60], xx + 6, ly, k.zero? ? WHITE : [180, 190, 215], a)
      end
    end

    def flash_overlay
      s = @sim
      f = s.flash
      return if f < 0.05

      c = @canvas
      lc = s.last_compact
      compact = lc && s.tick - lc[:tick] < 30
      col = compact ? [200, 255, 255] : MAGENTA
      c.rect(WX, WY, Simulation::WORLD_W, Simulation::WORLD_H, col, (f * 70).to_i)
      4.times { |k| c.rect(0, k, W, 1, col, (f * 255).to_i) && c.rect(0, H - 1 - k, W, 1, col, (f * 255).to_i) }
      return unless compact

      msg = "ENLIGHTENMENT // GC.compact moved #{lc[:moved]} objects in #{lc[:ms]}ms"
      tw = c.text_width(msg, font: :large)
      mx = WX + (Simulation::WORLD_W - tw) / 2
      my = WY + Simulation::WORLD_H / 2 - 10
      c.rect(mx - 12, my - 8, tw + 24, 36, [0, 0, 0], (f * 200).to_i)
      c.text(msg, mx, my, WHITE, (f * 255 + 60).clamp(0, 255).to_i, font: :large)
      sub = "top movers: #{lc[:top].join('  ')}"
      c.text(sub, WX + (Simulation::WORLD_W - c.text_width(sub)) / 2, my + 26, CYAN, (f * 255 + 60).clamp(0, 255).to_i)
    end
  end
end
