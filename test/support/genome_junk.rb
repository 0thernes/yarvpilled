# frozen_string_literal: true

# Hostile genome trees: mostly grammar-shaped, salted with wrong arities,
# unknown operators/variables, out-of-range literals, floats, strings, nils.
# Shared by test_properties.rb and tools/genome_fuzz.rb.
module GenomeJunk
  G = Yarvpilled::Genome

  module_function

  def tree(g)
    stmts = Array.new(g.int(0, 5)) { [g.pick(%i[let let let def]), g.pick(G::LOCALS + %i[x fa]), expr(g, 3)] }
    [stmts, expr(g, 4)]
  end

  def expr(g, depth)
    return leaf(g) if depth <= 0 || g.int(0, 3).zero?

    sub = -> { expr(g, depth - 1) }
    case g.int(0, 11)
    when 0, 1 then [:op, g.pick(G::OPS + %i[/ ** <<]), sub.call, sub.call]
    when 2 then [:mul, sub.call, sub.call]
    when 3 then [:mod, sub.call, g.pick([0, 1, 7, 4096, 4097, -3, 2.0])]
    when 4 then [:shr, sub.call, g.pick([0, 3, 62, 63, -1])]
    when 5 then [g.pick(%i[max min]), sub.call, sub.call]
    when 6, 7 then [:if, [:cmp, g.pick(G::CMPS + %i[<= !=]), sub.call, sub.call], sub.call, sub.call]
    when 8 then [:if, sub.call, sub.call, sub.call]
    when 9 then [:op, :+, sub.call]
    else leaf(g)
    end
  end

  def leaf(g)
    case g.int(0, 9)
    when 0 then [:n, g.pick([0, -1, 7, G::INT_LIMIT, G::INT_LIMIT + 1, 1.5, "1", nil])]
    when 1 then [:v, g.pick(%i[fa en t0 t3 zz __id__])]
    when 2 then g.pick([[], 3, nil, [:n], [:v, "fa"]])
    when 3..6 then [:v, g.pick(G::SENSORS)]
    else [:n, g.int(-100, 100)]
    end
  end
end
