# frozen_string_literal: true

require "io/console"

module Yarvpilled
  # ANSI truecolor terminal view. The world is drawn with upper-half blocks
  # (two pixels per cell); side panels show live disasm, opcode bars, GC and
  # Ractor votes. All values come straight from the running Simulation.
  class TUI
    ESC = "\e["

    def initialize(sim, out: $stdout, cols: nil, rows: nil)
      @sim = sim
      @out = out
      wr, wc = (out.respond_to?(:winsize) && out.tty? ? out.winsize : [40, 132])
      @cols = cols || wc
      @rows = rows || wr
      @frame = 0
    end

    def run(frames: nil, ticks_per_frame: 1, fps: 20)
      @out.print "#{ESC}?25l#{ESC}2J"
      trap("INT") { @stop = true }
      loop do
        break if @stop || (frames && @frame >= frames)

        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        ticks_per_frame.times { @sim.step! }
        @out.write(render)
        @out.flush
        dt = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
        sleep(1.0 / fps - dt) if dt < 1.0 / fps
      end
    ensure
      @out.print "#{ESC}0m#{ESC}?25h\n"
    end

    def fg(c) = "#{ESC}38;2;#{c[0]};#{c[1]};#{c[2]}m"
    def bg(c) = "#{ESC}48;2;#{c[0]};#{c[1]};#{c[2]}m"

    def render
      @frame += 1
      s = @sim
      side_w = 54
      ww = [[@cols - side_w - 3, 40].max, 160].min
      wh = [@rows - 4, 12].max
      pix = world_pixels(ww, wh * 2)
      side = side_lines(side_w, wh)
      buf = +"#{ESC}H"
      title = " YARVPILLED // pure ISeq cognition // zero models "
      stats = format(" t=%d gen=%d pop=%d species=%d births=%d rewrites=%d compacts=%d %s",
                     s.tick, s.max_gen, s.alive_count, s.live_species.size, s.births_total, s.rewrites_total, s.compacts,
                     s.yjit_snapshot ? "+YJIT" : "")
      buf << bg([30, 6, 40]) << fg([255, 60, 210]) << "#{ESC}1m" << title << "#{ESC}22m" << fg([255, 190, 60]) << stats[0, [@cols - title.size, 0].max].ljust([@cols - title.size, 0].max) << "#{ESC}0m\n"
      wh.times do |row|
        last_f = last_b = nil
        ww.times do |col|
          top = pix[row * 2][col]
          bot = pix[row * 2 + 1][col]
          buf << fg(top) if top != last_f
          buf << bg(bot) if bot != last_b
          last_f = top
          last_b = bot
          buf << "\u2580"
        end
        buf << "#{ESC}0m " << (side[row] || "") << "#{ESC}0m#{ESC}K\n"
      end
      ev = s.events.last
      buf << fg([180, 190, 220]) << (ev ? " t#{ev[:tick]} #{ev[:text]}" : " booting...")[0, @cols - 1] << "#{ESC}0m#{ESC}K"
      buf
    end

    private

    def world_pixels(w, h)
      s = @sim
      fw, fh, = s.world.food_dims
      food = s.world.food_bytes
      grid = Array.new(h) do |y|
        fy = y * fh / h
        Array.new(w) do |x|
          v = food.getbyte(fy * fw + x * fw / w)
          [4 + v / 12, 8 + v * 2 / 5, 16 + v / 3]
        end
      end
      snap = s.world.snapshot
      sx = w.to_f / Simulation::WORLD_W
      sy = h.to_f / Simulation::WORLD_H
      apex = s.apex_id
      (0...snap.size).step(8) do |i|
        sp = s.species[snap[i + 5]]
        next unless sp

        x = (snap[i + 1] * sx).to_i.clamp(0, w - 1)
        y = (snap[i + 2] * sy).to_i.clamp(0, h - 1)
        grid[y][x] = sp.id == apex && (@frame / 4).even? ? [255, 255, 255] : sp.color
      end
      grid
    end

    def side_lines(w, h)
      s = @sim
      lines = []
      ap = s.apex
      cyan = fg([0, 235, 255])
      mag = fg([255, 50, 200])
      dim = fg([110, 120, 160])
      lines << "#{mag}#{ESC}1mAPEX ##{ap&.id} think() disasm#{ESC}22m #{dim}#{ap&.genome&.bytecode_len}w gen#{ap&.gen}"
      if ap&.mind
        dis = RubyVM::InstructionSequence.of(ap.mind.class.instance_method(:think)).disasm.lines.drop(3).map(&:rstrip)
        n = [h / 2 - 2, 4].max
        off = dis.size > n ? (@frame / 3) % (dis.size - n + 1) : 0
        dis[off, n].each do |ln|
          if (m = ln.match(/\A(\d{4}) (\S+)\s*(.*)\z/))
            lines << "#{dim}#{m[1]} #{m[2].start_with?('branch', 'jump') ? fg([255, 190, 50]) : cyan}#{m[2].ljust(22)}#{fg([200, 210, 230])}#{m[3].strip.gsub(/\s+/, ' ')[0, w - 28]}"
          else
            lines << "#{dim}#{ln.strip[0, w]}"
          end
        end
      end
      lines << ""
      lines << "#{cyan}#{ESC}1mOPCODES (population)#{ESC}22m"
      agg = Hash.new(0)
      s.live_species.each { |sp| sp.genome.histogram.each { |k, v| agg[k] += v * sp.alive } }
      top = agg.sort_by { -_2 }.first(5)
      mx = top.first&.last.to_f
      top.each_with_index do |(op, v), k|
        col = Genome.hsv(190 + k * 25, 0.85, 1.0)
        bar = "\u2588" * (mx.positive? ? (22 * v / mx).to_i : 0)
        lines << "#{fg([190, 200, 230])}#{op.to_s[0, 20].ljust(20)} #{fg(col)}#{bar} #{v}"
      end
      g = s.gc_snapshot
      lines << "#{fg([120, 255, 140])}GC #{g[:count]} (maj #{g[:major_gc_count]}) live #{g[:heap_live_slots]} compact #{s.compacts}"
      votes = Experts::ROSTER.first(s.ractor_count).map do |name, _|
        v = s.votes[name].last
        v ? "#{fg(v[:color])}\u25A0" : "#{dim}\u25A1"
      end
      lines << "#{fg([170, 110, 255])}RACTORS #{votes.join(' ')} #{dim}fibers #{s.fiber_switches}/tick"
      lines.first(h)
    end
  end
end
