# frozen_string_literal: true

require_relative "world_ruby"

module Yarvpilled
  # Loads the ruby.h C extension if it was compiled (rake compile).
  # If it is missing or fails to load (e.g. no compiler on Windows), every
  # component falls back to its bit-identical pure-Ruby twin.
  # Set YARVPILLED_PURE=1 to force the pure-Ruby path.
  module Native
    begin
      raise LoadError, "YARVPILLED_PURE set" if ENV["YARVPILLED_PURE"].to_s =~ /\A(1|true|yes)\z/i

      begin
        require_relative "yarvpilled_native"
      rescue LoadError
        require "yarvpilled/yarvpilled_native" # installed gem: extension lives in the gem's extension dir
      end
      AVAILABLE = true
    rescue LoadError
      AVAILABLE = false
    end
  end

  module World
    KINDS = %i[native c asm rust ruby].freeze

    module_function

    # :native/:c -> C kernel, :asm -> C kernel with hand-written x86-64 crowd
    # scan, :rust -> Rust kernel, :ruby -> pure Ruby (WorldRuby).
    def build(kind, w, h, cell, cap)
      case kind
      when :native, :c, :asm, :rust
        raise "C extension not compiled; run `rake compile` or use --world=ruby" unless Native::AVAILABLE

        Native::World.new(w, h, cell, cap, kind == :native ? :c : kind)
      when :ruby then WorldRuby.new(w, h, cell, cap)
      else raise ArgumentError, "unknown world #{kind}"
      end
    end

    def available?(kind)
      return true if kind == :ruby
      return false unless Native::AVAILABLE

      Native::World.new(72, 72, 8, 1, kind == :native ? :c : kind)
      true
    rescue NotImplementedError
      false
    end
  end
end
