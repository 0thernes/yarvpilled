# frozen_string_literal: true

require "digest"

module Yarvpilled
  # Bit-exact fingerprints of world state, used to check correctness next to
  # every benchmark timing and in replication runs. Floats are hashed by their
  # IEEE-754 bit pattern, so "equal digest" means bit-identical state.
  module StateDigest
    module_function

    def world(w)
      snap = w.snapshot.map { |v| v.is_a?(Float) ? [v].pack("E").unpack1("Q<") : v }
      Digest::SHA256.hexdigest("#{snap.join(',')}|#{w.food_bytes.unpack1('H*')}|#{w.stats.values_at(:alive, :eaten, :deaths, :ticks).join(',')}")[0, 16]
    end
  end
end
