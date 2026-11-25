# frozen_string_literal: true

# YP_LIB: load the library from another tree (tools/mutate.rb runs the suite against mutants)
$LOAD_PATH.unshift(ENV["YP_LIB"] || File.expand_path("../lib", __dir__))
Warning[:experimental] = false
# Windows (Ruby 3.4.9 mingw, minitest 5.25): minitest's idle parallel-executor threads plus the
# Ractor vote deadlock test_events_ractors_and_gc_compact_happen_for_real at the third vote (tick
# 120). No test here uses parallelize_me!, so run without executor threads there.
ENV["MT_CPU"] ||= "0" if Gem.win_platform?
require "minitest/autorun"
require "yarvpilled"
