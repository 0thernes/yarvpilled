# frozen_string_literal: true

module Yarvpilled
  # "Constitutional AI = Refinements." The world only understands actions
  # 0..3. This refinement is activated lexically (`using Guardrails`) in
  # simulation.rb only, so the genome bytecode itself never sees it: brains
  # may compute any Integer they like, and the guardrail clamps it at the
  # boundary where thought becomes action.
  module Guardrails
    refine Integer do
      def to_action = self & 3
    end

    refine NilClass do
      def to_action = 0
    end
  end

  # "Jailbreaks as prepend chains." When a once-thriving species collapses
  # to a handful of members, a survival instinct is prepended onto its mind's
  # singleton class. It overrides think when starving and otherwise calls
  # `super` into the evolved bytecode.
  module Instinct
    def think(fa, fl, fr, en, cr, ag)
      en < 20 ? (fl > fr ? 1 : 2) : super
    end
  end

  # Base class for per-species minds; each species gets
  # Class.new(Mind) { define_method(:think, &genome.brain) }.
  class Mind
    attr_reader :species_id

    def initialize(species_id) = @species_id = species_id
  end
end
