# frozen_string_literal: true

require_relative "trig_table"

module Yarvpilled
  # Pure-Ruby port of ext/yarvpilled_native/world.c. Same API, same integer
  # and IEEE-754 arithmetic in the same order, so both tiers produce
  # bit-identical worlds for identical inputs (see test_world_equivalence).
  # This is the "pure Ruby interpreter" tier of the benchmark.
  class WorldRuby
    NDIR = 64
    SENSORS = 6
    RADIUS = 4.0
    CROWD_R = 20.0
    MAX_AGE = 900
    FOOD_MAX = 255
    COS_T = TrigTable::COS # literal bit patterns shared with the C kernel (no libm dependence)
    SIN_T = TrigTable::SIN

    def initialize(width, height, food_cell, capacity)
      raise ArgumentError, "bad world params" if food_cell <= 0 || capacity <= 0

      @w = width.to_f
      @h = height.to_f
      @fcell = food_cell
      @cap = capacity
      @fw = (@w / @fcell).to_i
      @fh = (@h / @fcell).to_i
      @gcell = 24
      @gw = (@w / @gcell).ceil
      @gh = (@h / @gcell).ceil
      @used = 0
      @x = Array.new(@cap, 0.0)
      @y = Array.new(@cap, 0.0)
      @heading = Array.new(@cap, 0)
      @age = Array.new(@cap, 0)
      @species = Array.new(@cap, 0)
      @cost = Array.new(@cap, 0)
      @last_action = Array.new(@cap, 0)
      @energy = Array.new(@cap, 0)
      @alive = Array.new(@cap, false)
      nf = @fw * @fh
      @food = Array.new(nf, 0)
      @fert = Array.new(nf, 0)
      @facc = Array.new(nf, 0)
      @ghead = Array.new(@gw * @gh, -1)
      @gnext = Array.new(@cap, -1)
      @eaten_total = 0
      @ticks = 0
      @deaths_total = 0
    end

    attr_reader :used

    def sense(out)
      build_grid
      alive = 0
      cr2 = CROWD_R * CROWD_R
      @used.times do |i|
        base = i * SENSORS
        unless @alive[i]
          SENSORS.times { |k| out[base + k] = 0 }
          next
        end
        alive += 1
        h = @heading[i]
        hl = (h - 6) & (NDIR - 1)
        hr = (h + 6) & (NDIR - 1)
        px = @x[i]
        py = @y[i]
        fa = @food[food_index(px + COS_T[h] * 10.0, py + SIN_T[h] * 10.0)]
        fl = @food[food_index(px + COS_T[hl] * 10.0, py + SIN_T[hl] * 10.0)]
        fr = @food[food_index(px + COS_T[hr] * 10.0, py + SIN_T[hr] * 10.0)]
        en = (@energy[i] / 4.0).truncate
        en = 255 if en > 255
        en = 0 if en.negative?
        ag = @age[i] / 8
        ag = 255 if ag > 255
        cr = 0
        gx = (px / @gcell).to_i
        gy = (py / @gcell).to_i
        -1.upto(1) do |oy|
          -1.upto(1) do |ox|
            cx = (gx + ox + @gw) % @gw
            cy = (gy + oy + @gh) % @gh
            j = @ghead[cy * @gw + cx]
            while j >= 0
              if j != i
                dx = tdelta(px, @x[j], @w)
                dy = tdelta(py, @y[j], @h)
                cr += 1 if dx * dx + dy * dy < cr2
              end
              j = @gnext[j]
            end
          end
        end
        cr = 15 if cr > 15
        out[base] = fa
        out[base + 1] = fl
        out[base + 2] = fr
        out[base + 3] = en
        out[base + 4] = cr
        out[base + 5] = ag
      end
      alive
    end

    def act(actions, thresh)
      births = []
      deaths = []
      alen = actions.size
      nf = @fw * @fh
      food = @food
      facc = @facc
      fert = @fert
      c = 0
      while c < nf
        acc = facc[c] + fert[c]
        f = food[c] + (acc >> 8)
        facc[c] = acc & 255
        food[c] = f > FOOD_MAX ? FOOD_MAX : f
        c += 1
      end

      @used.times do |i|
        next unless @alive[i]

        a = i < alen ? (actions[i] & 3) : 0
        @last_action[i] = a
        speed =
          case a
          when 0 then 0.35
          when 1 then @heading[i] = (@heading[i] - 3) & (NDIR - 1); 1.0
          when 2 then @heading[i] = (@heading[i] + 3) & (NDIR - 1); 1.0
          else 2.4
          end
        h = @heading[i]
        @x[i] = wrapd(@x[i] + COS_T[h] * speed, @w)
        @y[i] = wrapd(@y[i] + SIN_T[h] * speed, @h)
        fc = food_index(@x[i], @y[i])
        bite = a.zero? ? 9 : 4
        take = food[fc] < bite ? food[fc] : bite
        food[fc] -= take
        @eaten_total += take
        @energy[i] += take + take / 2
        @energy[i] -= 3 + @cost[i] + (a == 3 ? 3 : 0)
        @age[i] += 1
      end

      build_grid
      lim = (2 * RADIUS) * (2 * RADIUS)
      @used.times do |i|
        next unless @alive[i]

        gx = (@x[i] / @gcell).to_i
        gy = (@y[i] / @gcell).to_i
        -1.upto(1) do |oy|
          -1.upto(1) do |ox|
            cx = (gx + ox + @gw) % @gw
            cy = (gy + oy + @gh) % @gh
            j = @ghead[cy * @gw + cx]
            while j >= 0
              if j > i
                dx = tdelta(@x[i], @x[j], @w)
                dy = tdelta(@y[i], @y[j], @h)
                d2 = dx * dx + dy * dy
                if d2 < lim && d2 != 0.0
                  d = Math.sqrt(d2)
                  push = (2 * RADIUS - d) * 0.5 / d
                  @x[i] = wrapd(@x[i] - dx * push, @w)
                  @y[i] = wrapd(@y[i] - dy * push, @h)
                  @x[j] = wrapd(@x[j] + dx * push, @w)
                  @y[j] = wrapd(@y[j] + dy * push, @h)
                end
              end
              j = @gnext[j]
            end
          end
        end
      end

      @used.times do |i|
        next unless @alive[i]

        if @energy[i] <= 0 || @age[i] >= MAX_AGE
          @alive[i] = false
          fc = food_index(@x[i], @y[i])
          f = food[fc] + 40
          food[fc] = f > FOOD_MAX ? FOOD_MAX : f
          @deaths_total += 1
          deaths << i
        elsif @energy[i] >= thresh
          births << i
        end
      end
      @ticks += 1
      [births, deaths]
    end

    def spawn(x, y, heading, energy, species_id, cost)
      slot = (0...@used).find { |i| !@alive[i] }
      unless slot
        return nil if @used >= @cap

        slot = @used
        @used += 1
      end
      @x[slot] = wrapd(x.to_f, @w)
      @y[slot] = wrapd(y.to_f, @h)
      @heading[slot] = heading & (NDIR - 1)
      @energy[slot] = energy
      @species[slot] = species_id
      @cost[slot] = cost
      @age[slot] = 0
      @alive[slot] = true
      @last_action[slot] = 0
      slot
    end

    def split(i)
      return 0 if i.negative? || i >= @used || !@alive[i]

      half = (@energy[i] / 2.0).truncate
      @energy[i] -= half
      half - 20
    end

    def feed(i, amt)
      @energy[i] += amt if i >= 0 && i < @used && @alive[i]
      nil
    end

    def set_species(i, sid, cost)
      return unless i >= 0 && i < @used

      @species[i] = sid
      @cost[i] = cost
    end

    def fertility=(str)
      raise ArgumentError, "fertility must be #{@fw * @fh} bytes" if str.bytesize != @fw * @fh

      @fert = str.bytes
    end

    def fill_food(v) = @food.fill(v & 255) && nil
    def food_bytes = @food.pack("C*")
    def species_of(i) = @species[i]
    def alive?(i) = i >= 0 && i < @used && @alive[i]
    def food_dims = [@fw, @fh, @fcell]

    def snapshot
      out = []
      @used.times do |i|
        next unless @alive[i]

        out.push(i, @x[i], @y[i], @heading[i], @energy[i], @species[i], @age[i], @last_action[i])
      end
      out
    end

    def stats
      { alive: @alive.count(true), food: @food.sum, eaten: @eaten_total, deaths: @deaths_total, ticks: @ticks }
    end

    private

    def food_index(x, y)
      cx = (x / @fcell).to_i % @fw
      cy = (y / @fcell).to_i % @fh
      cy * @fw + cx
    end

    def wrapd(v, m)
      v += m if v.negative?
      v -= m if v >= m
      v
    end

    def tdelta(a, b, m)
      d = b - a
      d -= m if d > m / 2
      d += m if d < -m / 2
      d
    end

    def build_grid
      @ghead.fill(-1)
      @used.times do |i|
        next unless @alive[i]

        c = ((@y[i] / @gcell).to_i % @gh) * @gw + ((@x[i] / @gcell).to_i % @gw)
        @gnext[i] = @ghead[c]
        @ghead[c] = i
      end
    end
  end
end
