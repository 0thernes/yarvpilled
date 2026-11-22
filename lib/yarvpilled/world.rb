# frozen_string_literal: true

require_relative "world_ruby"

module Yarvpilled
  # Loads the ruby.h C extension if it was compiled (rake compile).
  module Native
    begin
      require_relative "yarvpilled_native"
      AVAILABLE = true
    rescue LoadError
      AVAILABLE = false
    end
  end

  module World
    module_function

    def build(kind, w, h, cell, cap)
      case kind
      when :native
        raise "C extension not compiled; run `rake compile` or use --world=ruby" unless Native::AVAILABLE

        Native::World.new(w, h, cell, cap)
      when :ruby then WorldRuby.new(w, h, cell, cap)
      else raise ArgumentError, "unknown world #{kind}"
      end
    end
  end
end
