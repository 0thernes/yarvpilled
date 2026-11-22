# frozen_string_literal: true

require_relative "../../lib/yarvpilled/trig_table"

module Yarvpilled
  # Deliberately simple, slow reference stepper for differential testing.
  #
  # It is written from the rules (docs/architecture.md), not translated from a
  # backend: no spatial grid, no linked lists, no incremental tricks. Every
  # neighbour query is an O(n^2) scan with the rule spelled out directly:
  # "j is a neighbour of i if j's grid cell is within one cell of i's (on the
  # torus of grid cells) and j is within the radius". The fast backends must
  # agree with it bit for bit.
  class ReferenceWorld
    GRID = 24
    BITE = { 0 => 9, 1 => 4, 2 => 4, 3 => 4 }.freeze
    SPEED = { 0 => 0.35, 1 => 1.0, 2 => 1.0, 3 => 2.4 }.freeze
    TURN = { 0 => 0, 1 => -3, 2 => 3, 3 => 0 }.freeze

    Creature = Struct.new(:x, :y, :heading, :energy, :species, :cost, :age, :last_action, :alive)

    def initialize(width, height, food_cell, capacity)
      @w = width.to_f
      @h = height.to_f
      @fcell = food_cell
      @cap = capacity
      @fw = (@w / @fcell).to_i
      @fh = (@h / @fcell).to_i
      @gw = (@w / GRID).ceil
      @gh = (@h / GRID).ceil
      @slots = []
      @food = Array.new(@fw * @fh, 0)
      @fert = Array.new(@fw * @fh, 0)
      @facc = Array.new(@fw * @fh, 0)
      @eaten = 0
      @deaths = 0
      @ticks = 0
    end

    def used = @slots.size

    def spawn(x, y, heading, energy, species, cost)
      slot = @slots.index { |c| !c.alive }
      if slot.nil?
        return nil if @slots.size >= @cap

        slot = @slots.size
      end
      @slots[slot] = Creature.new(wrap(x.to_f, @w), wrap(y.to_f, @h), heading % 64, energy, species, cost, 0, 0, true)
      slot
    end

    def split(i)
      c = @slots[i]
      return 0 unless c&.alive

      half = (c.energy / 2.0).truncate
      c.energy -= half
      half - 20
    end

    def fertility=(str)
      @fert = str.bytes
    end

    def fill_food(v)
      @food.fill(v % 256)
      nil
    end

    def food_bytes = @food.pack("C*")

    def snapshot
      @slots.each_with_index.flat_map do |c, i|
        c.alive ? [i, c.x, c.y, c.heading, c.energy, c.species, c.age, c.last_action] : []
      end
    end

    def stats
      { alive: @slots.count(&:alive), food: @food.sum, eaten: @eaten, deaths: @deaths, ticks: @ticks }
    end

    def sense(out)
      @slots.each_with_index do |c, i|
        unless c.alive
          6.times { |k| out[i * 6 + k] = 0 }
          next
        end
        probe = lambda do |dir|
          d = dir % 64
          @food[food_cell(c.x + TrigTable::COS[d] * 10.0, c.y + TrigTable::SIN[d] * 10.0)]
        end
        crowd = @slots.each_index.count do |j|
          j != i && @slots[j].alive && near_cell?(c, @slots[j]) &&
            dist2(c.x, c.y, @slots[j].x, @slots[j].y) < 20.0 * 20.0
        end
        out[i * 6] = probe.call(c.heading)
        out[i * 6 + 1] = probe.call(c.heading - 6)
        out[i * 6 + 2] = probe.call(c.heading + 6)
        out[i * 6 + 3] = (c.energy / 4.0).truncate.clamp(0, 255)
        out[i * 6 + 4] = [crowd, 15].min
        out[i * 6 + 5] = [c.age / 8, 255].min
      end
      @slots.count(&:alive)
    end

    def act(actions, thresh)
      regrow
      move_and_eat(actions)
      collide
      reap(thresh)
    end

    private

    def regrow
      @food.each_index do |k|
        acc = @facc[k] + @fert[k]
        @facc[k] = acc % 256
        @food[k] = [@food[k] + acc / 256, 255].min
      end
    end

    def move_and_eat(actions)
      @slots.each_with_index do |c, i|
        next unless c.alive

        a = (actions[i] || 0) % 4
        c.last_action = a
        c.heading = (c.heading + TURN[a]) % 64
        c.x = wrap(c.x + TrigTable::COS[c.heading] * SPEED[a], @w)
        c.y = wrap(c.y + TrigTable::SIN[c.heading] * SPEED[a], @h)
        k = food_cell(c.x, c.y)
        take = [@food[k], BITE[a]].min
        @food[k] -= take
        @eaten += take
        c.energy += take + take / 2 - (3 + c.cost + (a == 3 ? 3 : 0))
        c.age += 1
      end
    end

    # Pairs (i, j>i) are resolved in the order the rules define: i ascending;
    # for each i, the 9 neighbour cells row by row (dy -1..1, dx -1..1) around
    # i's current cell; within a cell, higher slot first. Cell membership is
    # taken after movement, before any push.
    def collide
      member = @slots.map { |c| c.alive ? cell_of(c.x, c.y) : nil }
      @slots.each_with_index do |ci, i|
        next unless ci.alive

        gx = (ci.x / GRID).to_i # i's cell is fixed before its own pushes
        gy = (ci.y / GRID).to_i
        [-1, 0, 1].each do |oy|
          [-1, 0, 1].each do |ox|
            target = [(gx + ox) % @gw, (gy + oy) % @gh]
            (@slots.size - 1).downto(i + 1) do |j|
              next unless member[j] == target

              cj = @slots[j]
              dx = tdelta(ci.x, cj.x, @w)
              dy = tdelta(ci.y, cj.y, @h)
              d2 = dx * dx + dy * dy
              next unless d2 < 8.0 * 8.0 && d2 != 0.0

              d = Math.sqrt(d2)
              push = (8.0 - d) * 0.5 / d
              ci.x = wrap(ci.x - dx * push, @w)
              ci.y = wrap(ci.y - dy * push, @h)
              cj.x = wrap(cj.x + dx * push, @w)
              cj.y = wrap(cj.y + dy * push, @h)
            end
          end
        end
      end
    end

    def reap(thresh)
      births = []
      deaths = []
      @slots.each_with_index do |c, i|
        next unless c.alive

        if c.energy <= 0 || c.age >= 900
          c.alive = false
          k = food_cell(c.x, c.y)
          @food[k] = [@food[k] + 40, 255].min
          @deaths += 1
          deaths << i
        elsif c.energy >= thresh
          births << i
        end
      end
      @ticks += 1
      [births, deaths]
    end

    def cell_of(x, y) = [(x / GRID).to_i % @gw, (y / GRID).to_i % @gh]

    def near_cell?(a, b)
      ax, ay = (a.x / GRID).to_i, (a.y / GRID).to_i
      bx, by = cell_of(b.x, b.y)
      cyc = ->(p, q, n) { [(p - q) % n, (q - p) % n].min <= 1 }
      cyc.call(ax, bx, @gw) && cyc.call(ay, by, @gh)
    end

    def food_cell(x, y) = ((y / @fcell).to_i % @fh) * @fw + ((x / @fcell).to_i % @fw)
    def dist2(ax, ay, bx, by)
      dx = tdelta(ax, bx, @w)
      dy = tdelta(ay, by, @h)
      dx * dx + dy * dy
    end

    def wrap(v, m)
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
  end
end
