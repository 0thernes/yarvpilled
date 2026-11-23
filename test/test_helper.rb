# frozen_string_literal: true

# YP_LIB: load the library from another tree (tools/mutate.rb runs the suite against mutants)
$LOAD_PATH.unshift(ENV["YP_LIB"] || File.expand_path("../lib", __dir__))
Warning[:experimental] = false
require "minitest/autorun"
require "yarvpilled"
