# frozen_string_literal: true

module Yarvpilled
  # Ractor hive-mind: N isolated Ractor "experts" each receive a deeply
  # frozen (Ractor.make_shareable) table of candidate species and vote for
  # one according to their own taste over the real opcode histograms. The
  # winning species is "blessed" with energy. Votes really run in parallel
  # Ractors; latencies are measured inside each Ractor.
  module Experts
    ROSTER = [
      ["BRANCH-ORACLE", :branch], ["ARITH-SMITH", :arith], ["LEAN-MONK", :lean],
      ["STACK-WITCH", :stack], ["HERD-MIND", :herd], ["CONST-SAGE", :const]
    ].freeze

    module_function

    # Pure function: safe to call from any Ractor.
    def score(taste, cand)
      _sid, hist, len, alive, births = cand
      total = hist.values.sum.nonzero? || 1
      sum = ->(pred) { hist.sum { |k, v| pred.call(k.to_s) ? v : 0 } }
      case taste
      when :branch then sum.call(->(k) { k.start_with?("branch", "jump") }) * 1000 / total
      when :arith then sum.call(->(k) { k =~ /opt_(plus|minus|mult|mod|and|or)/ }) * 1000 / total
      when :lean then 100_000 / (len + 1)
      when :stack then hist.size * 100 + births
      when :herd then alive * 3 + births
      when :const then sum.call(->(k) { k.start_with?("putobject") }) * 1000 / total
      else 0
      end
    end

    def spawn_all(count)
      ROSTER.first(count).map do |name, taste|
        Ractor.new(name, taste, name: name) do |nm, tst|
          loop do
            epoch, cands = Ractor.receive
            break if epoch == :stop

            t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
            best = cands.max_by { |c| [Yarvpilled::Experts.score(tst, c), -c[0]] }
            sc = best ? Yarvpilled::Experts.score(tst, best) : 0
            dt = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) - t0
            Ractor.yield [nm, epoch, best && best[0], sc, dt, Ractor.current.object_id]
          end
        end
      end
    end
  end
end
