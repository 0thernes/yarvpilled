# frozen_string_literal: true

require "zlib"

module Yarvpilled
  # A creature's genome: a tiny expression program that is rendered to Ruby
  # source, compiled by RubyVM::InstructionSequence, serialized with
  # #to_binary, and re-instantiated with .load_from_binary. The resulting
  # lambda's block ISeq is the brain YARV executes every tick.
  #
  # Genome tree nodes (plain frozen arrays, so they are Ractor-shareable):
  #   [:n, Integer]            literal
  #   [:v, Symbol]             sensor or local variable
  #   [:op, sym, a, b]         + - ^ | &         (always Integer)
  #   [:mul, a, b]             ((a * b) & 4095)  bounded so no Bignums
  #   [:mod, a, k]             (a % k), k > 0 literal
  #   [:shr, a, k]             (a >> k)
  #   [:max, a, b] / [:min..]  [a, b].max  (opt_newarray_send)
  #   [:if, cond, a, b]        (cond ? a : b)
  #   cond: [:cmp, sym, a, b]  < > ==
  class Genome
    # Raised for any tree outside the genome grammar. Validation happens before
    # anything is rendered or compiled, so a bad genome never reaches YARV.
    class InvalidGenome < ArgumentError; end

    SENSORS = %i[fa fl fr en cr ag].freeze
    LOCALS = %i[t0 t1 t2 t3].freeze
    OPS = %i[+ - ^ | &].freeze
    CMPS = %i[< > ==].freeze
    MAX_STMTS = 4
    MAX_DEPTH = 4
    PARAMS = "fa, fl, fr, en, cr, ag"
    INT_LIMIT = 1 << 31   # |literal| bound (dream constants are small class/method counts)
    NODE_LIMIT = 512      # total nodes per genome
    DEPTH_LIMIT = 48

    # Hand-written ancestor: graze when food is ahead, otherwise steer toward
    # the richer side. Everything else evolves from here.
    SEED_STMTS = [[:let, :t0, [:op, :-, [:v, :fl], [:v, :fr]]]].freeze
    SEED_RET = [:if, [:cmp, :>, [:v, :fa], [:n, 30]], [:n, 0],
                [:if, [:cmp, :>, [:v, :t0], [:n, 0]], [:n, 1], [:n, 2]]].freeze

    attr_reader :stmts, :ret, :source, :binary, :iseq, :brain, :histogram, :bytecode_len, :dream

    def self.seed = new(SEED_STMTS, SEED_RET)

    def self.deep_freeze(obj)
      obj.each { |e| deep_freeze(e) if e.is_a?(Array) } if obj.is_a?(Array)
      obj.freeze
    end

    def initialize(stmts, ret, dream: nil)
      self.class.validate!(stmts, ret)
      @stmts = self.class.deep_freeze(stmts.map(&:dup))
      @ret = self.class.deep_freeze(ret)
      @dream = dream
      @source = render
      compile!
    end

    # Strict grammar check. Every literal, symbol and shape is whitelisted, so
    # rendering can never inject code, divide by zero, or reference an
    # undefined local.
    def self.validate!(stmts, ret)
      raise InvalidGenome, "stmts must be an Array" unless stmts.is_a?(Array)
      raise InvalidGenome, "too many statements (#{stmts.size} > #{MAX_STMTS})" if stmts.size > MAX_STMTS

      count = [0]
      defined = []
      stmts.each do |st|
        unless st.is_a?(Array) && st.size == 3 && st[0] == :let && LOCALS.include?(st[1]) && !defined.include?(st[1])
          raise InvalidGenome, "bad statement #{st.inspect[0, 80]}"
        end

        check_expr(st[2], SENSORS + defined, 0, count)
        defined << st[1]
      end
      check_expr(ret, SENSORS + defined, 0, count)
      true
    end

    def self.check_expr(e, vars, depth, count)
      raise InvalidGenome, "genome too deep" if depth > DEPTH_LIMIT
      raise InvalidGenome, "genome too large" if (count[0] += 1) > NODE_LIMIT
      raise InvalidGenome, "node must be an Array, got #{e.class}" unless e.is_a?(Array) && !e.empty?

      int = ->(v, lo, hi) { v.is_a?(Integer) && v >= lo && v <= hi }
      sub = ->(x) { check_expr(x, vars, depth + 1, count) }
      ok =
        case e[0]
        when :n then e.size == 2 && int.(e[1], -INT_LIMIT, INT_LIMIT)
        when :v then e.size == 2 && vars.include?(e[1])
        when :op then e.size == 4 && OPS.include?(e[1]) && sub.(e[2]) && sub.(e[3])
        when :mul, :max, :min then e.size == 3 && sub.(e[1]) && sub.(e[2])
        when :mod then e.size == 3 && sub.(e[1]) && int.(e[2], 1, 4096)
        when :shr then e.size == 3 && sub.(e[1]) && int.(e[2], 0, 62)
        when :if then e.size == 4 && check_cond(e[1], vars, depth + 1, count) && sub.(e[2]) && sub.(e[3])
        else false
        end
      raise InvalidGenome, "bad node #{e.inspect[0, 80]}" unless ok

      true
    end

    def self.check_cond(c, vars, depth, count)
      raise InvalidGenome, "bad condition #{c.inspect[0, 80]}" unless c.is_a?(Array) && c.size == 4 && c[0] == :cmp && CMPS.include?(c[1])

      check_expr(c[2], vars, depth + 1, count) && check_expr(c[3], vars, depth + 1, count)
    end

    # Ruby source of the brain. Real code, compiled by YARV.
    def render
      body = @stmts.map { |(_, name, e)| "  #{name} = #{expr(e)}" }
      "->(#{PARAMS}) {\n#{(body + ["  #{expr(@ret)}"]).join("\n")}\n}"
    end

    # compile -> to_binary -> load_from_binary -> eval. The brain lambda is
    # instantiated from the serialized ISeq, so the binary IS the genome.
    def compile!
      wrapper = RubyVM::InstructionSequence.compile(@source, "genome", "genome", 1)
      @binary = wrapper.to_binary.freeze
      @brain = RubyVM::InstructionSequence.load_from_binary(@binary).eval
      @iseq = RubyVM::InstructionSequence.of(@brain)
      @histogram = Genome.opcode_histogram(@iseq)
      @bytecode_len = Genome.bytecode_length(@iseq)
    end

    def disasm = @iseq.disasm

    # Clone purely from the serialized bytecode (no source, no parser).
    def self.brain_from_binary(bin) = RubyVM::InstructionSequence.load_from_binary(bin).eval

    def self.instructions(iseq)
      out = []
      walk = lambda do |arr|
        arr[13].each do |ins|
          next unless ins.is_a?(Array)

          out << ins
          ins.each { |op| walk.call(op) if op.is_a?(Array) && op[0] == "YARVInstructionSequence/SimpleDataFormat" }
        end
      end
      walk.call(iseq.to_a)
      out
    end

    def self.opcode_histogram(iseq)
      instructions(iseq).each_with_object(Hash.new(0)) { |ins, h| h[ins[0]] += 1 }.freeze
    end

    def self.bytecode_length(iseq) = instructions(iseq).sum(&:size)

    # ---------------------------------------------------------------- body
    # Visible phenotype derived only from the real bytecode.
    ARITH = %i[opt_plus opt_minus opt_mult opt_mod opt_and opt_or opt_send_without_block].freeze
    BRANCH = %i[branchif branchunless jump branchnil].freeze
    COMPARE = %i[opt_lt opt_gt opt_eq opt_le opt_ge opt_neq].freeze

    def traits
      @traits ||= begin
        total = @histogram.values.sum.to_f
        share = ->(set) { set.sum { |k| @histogram[k] } / total }
        locals = @histogram.sum { |k, v| k.to_s.start_with?("getlocal", "setlocal") ? v : 0 } / total
        consts = @histogram.sum { |k, v| k.to_s.start_with?("putobject") ? v : 0 } / total
        arith = share.call(ARITH)
        branch = share.call(BRANCH)
        cmp = share.call(COMPARE)
        # Hue: a stable hash of the exact opcode multiset, so any change in
        # the bytecode's instruction mix is a visibly different species.
        sig = @histogram.sort.map { |k, v| "#{k}:#{v}" }.join(",")
        hue = (Zlib.crc32(sig) % 3600) / 10.0
        hue = (hue + arith * 40 - branch * 40 + cmp * 20 + consts * 10 - locals * 10) % 360
        {
          hue: hue.round(1),
          radius: (3.2 + Math.sqrt(@bytecode_len) * 0.55).clamp(3.5, 9.5).round(2),
          sides: 3 + (@histogram.size % 5),
          trail: (2 + @histogram.sum { |k, v| BRANCH.include?(k) ? v : 0 } * 2).clamp(2, 14),
          cost: 1 + (@bytecode_len / 22)
        }.freeze
      end
    end

    def color = Genome.hsv(traits[:hue], 0.78, 1.0)

    def self.hsv(h, s, v)
      c = v * s
      x = c * (1 - ((h / 60.0) % 2 - 1).abs)
      m = v - c
      r, g, b = case (h / 60).floor % 6
                when 0 then [c, x, 0]
                when 1 then [x, c, 0]
                when 2 then [0, c, x]
                when 3 then [0, x, c]
                when 4 then [x, 0, c]
                else [c, 0, x]
                end
      [((r + m) * 255).round, ((g + m) * 255).round, ((b + m) * 255).round]
    end

    # ------------------------------------------------------------ mutation
    # dreamer: optional callable returning [Integer, label] sourced from the
    # live heap (ObjectSpace) for "hallucinated" constants.
    def mutate(rng, dreamer: nil)
      stmts = @stmts.map { |s| s }
      ret = @ret
      dream = nil
      kind = rng.rand(100)
      if kind < 12 && stmts.size < MAX_STMTS
        name = (LOCALS - stmts.map { _2 }).first
        stmts.insert(rng.rand(stmts.size + 1), [:let, name, rand_expr(rng, 2, vars_before(stmts, stmts.size))]) if name
      elsif kind < 18 && !stmts.empty?
        stmts.delete_at(rng.rand(stmts.size))
      elsif kind < 30 && dreamer
        val, label = dreamer.call
        dream = label
        ret = replace_random(ret, rng, [:n, val], only: :n) || [:op, :^, ret, [:n, val]]
      elsif kind < 45 && !stmts.empty?
        i = rng.rand(stmts.size)
        stmts[i] = [:let, stmts[i][1], tweak(stmts[i][2], rng, vars_before(stmts, i))]
      else
        ret = tweak(ret, rng, vars_before(stmts, stmts.size))
      end
      stmts, ret = sanitize(stmts, ret)
      Genome.new(stmts, ret, dream: dream)
    end

    def to_h = { source: @source, len: @bytecode_len, histogram: @histogram, traits: traits }

    private

    def vars_before(stmts, i) = SENSORS + stmts.first(i).map { _2 }

    # Drop references to locals that no longer exist (after a deletion or
    # reorder) by replacing them with sensors, so the program always parses.
    def sanitize(stmts, ret)
      defined = []
      fixed = stmts.map do |(_, name, e)|
        e2 = fix_vars(e, SENSORS + defined)
        defined << name
        [:let, name, e2]
      end
      [fixed, fix_vars(ret, SENSORS + defined)]
    end

    def fix_vars(node, allowed)
      return node unless node.is_a?(Array)
      return(allowed.include?(node[1]) ? node : [:v, :fa]) if node[0] == :v

      node.map { |e| e.is_a?(Array) ? fix_vars(e, allowed) : e }
    end

    def tweak(node, rng, vars)
      r = rng.rand(100)
      if r < 30 then replace_random(node, rng, rand_expr(rng, 2, vars)) || node
      elsif r < 55 then replace_random(node, rng, [:n, rng.rand(64)], only: :n) || node
      elsif r < 70 then replace_random(node, rng, [:v, vars.sample(random: rng)], only: :v) || node
      elsif r < 85 then swap_op(node, rng)
      else depth(node) < MAX_DEPTH ? [:if, rand_cond(rng, 1, vars), node, rand_expr(rng, 1, vars)] : node
      end
    end

    def depth(node) = node.is_a?(Array) ? 1 + (node.map { depth(_1) }.max || 0) : 0

    def nodes(node, acc = [])
      return acc unless node.is_a?(Array) && node[0].is_a?(Symbol)

      acc << node
      node.each { |e| nodes(e, acc) if e.is_a?(Array) }
      acc
    end

    def replace_random(root, rng, replacement, only: nil)
      candidates = nodes(root).reject { |n| n[0] == :cmp }
      candidates = candidates.select { |n| n[0] == only } if only
      return nil if candidates.empty?

      target = candidates.sample(random: rng)
      substitute(root, target, replacement)
    end

    def substitute(node, target, replacement)
      return replacement if node.equal?(target)
      return node unless node.is_a?(Array)

      node.map { |e| e.is_a?(Array) ? substitute(e, target, replacement) : e }
    end

    def swap_op(root, rng)
      ops = nodes(root).select { |n| %i[op cmp max min].include?(n[0]) }
      return root if ops.empty?

      t = ops.sample(random: rng)
      repl = case t[0]
             when :op then [:op, (OPS - [t[1]]).sample(random: rng), t[2], t[3]]
             when :cmp then [:cmp, (CMPS - [t[1]]).sample(random: rng), t[2], t[3]]
             when :max then [:min, t[1], t[2]]
             else [:max, t[1], t[2]]
             end
      substitute(root, t, repl)
    end

    def rand_expr(rng, depth, vars)
      return(rng.rand < 0.55 ? [:v, vars.sample(random: rng)] : [:n, rng.rand(64)]) if depth <= 0

      case rng.rand(10)
      when 0..2 then [:op, OPS.sample(random: rng), rand_expr(rng, depth - 1, vars), rand_expr(rng, depth - 1, vars)]
      when 3 then [:mul, rand_expr(rng, depth - 1, vars), rand_expr(rng, depth - 1, vars)]
      when 4 then [:mod, rand_expr(rng, depth - 1, vars), 2 + rng.rand(9)]
      when 5 then [:shr, rand_expr(rng, depth - 1, vars), 1 + rng.rand(4)]
      when 6 then [rng.rand < 0.5 ? :max : :min, rand_expr(rng, depth - 1, vars), rand_expr(rng, depth - 1, vars)]
      when 7, 8 then [:if, rand_cond(rng, depth - 1, vars), rand_expr(rng, depth - 1, vars), rand_expr(rng, depth - 1, vars)]
      else [:v, vars.sample(random: rng)]
      end
    end

    def rand_cond(rng, depth, vars) = [:cmp, CMPS.sample(random: rng), rand_expr(rng, depth, vars), rand_expr(rng, 0, vars)]

    def expr(e)
      case e[0]
      when :n then e[1].to_s
      when :v then e[1].to_s
      when :op then "(#{expr(e[2])} #{e[1]} #{expr(e[3])})"
      when :mul then "((#{expr(e[1])} * #{expr(e[2])}) & 4095)"
      when :mod then "(#{expr(e[1])} % #{e[2]})"
      when :shr then "(#{expr(e[1])} >> #{e[2]})"
      when :max then "[#{expr(e[1])}, #{expr(e[2])}].max"
      when :min then "[#{expr(e[1])}, #{expr(e[2])}].min"
      when :if then "(#{expr(e[1])} ? #{expr(e[2])} : #{expr(e[3])})"
      when :cmp then "#{expr(e[2])} #{e[1]} #{expr(e[3])}"
      else raise ArgumentError, "bad node #{e.inspect}"
      end
    end
  end
end
