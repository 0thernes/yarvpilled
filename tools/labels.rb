#!/usr/bin/env ruby
# frozen_string_literal: true

# The repo's issue labels, and a one-shot sync through the GitHub CLI.
#   ruby tools/labels.rb             # create or update every label (gh label create --force)
#   ruby tools/labels.rb --dry-run   # print the gh commands only
#   ruby tools/labels.rb --list      # print the label table
# Uses `gh` auth; pass REPO=owner/name to target a repo other than the current one.

LABELS = [
  ["bug",              "d73a4a", "Something is broken"],
  ["enhancement",      "a2eeef", "New feature or improvement"],
  ["documentation",    "0075ca", "README, docs/, ADRs, comments"],
  ["question",         "d876e3", "Needs an answer, not a change"],
  ["good first issue", "7057ff", "Small, well-scoped, newcomer friendly"],
  ["help wanted",      "008672", "Extra hands welcome"],
  ["duplicate",        "cfd3d7", "Already tracked elsewhere"],
  ["wontfix",          "ffffff", "Out of scope for this project"],
  ["backend: ruby",    "cc342d", "Pure-Ruby world (world_ruby.rb)"],
  ["backend: c",       "555555", "C kernel / ruby.h glue (ext/yarvpilled_native)"],
  ["backend: asm",     "6e4a7e", "Hand-written x86-64 crowd scan"],
  ["backend: rust",    "dea584", "Rust kernel (ext/yarvpilled_rust)"],
  ["vm-internals",     "00ebff", "ISeq, TracePoint, Ractor, GC, YJIT mechanics"],
  ["visuals",          "ff2ec4", "Renderer, TUI, browser page, video"],
  ["benchmark",        "ffba30", "bench.rb, methodology, numbers"],
  ["science",          "78ff8c", "Selection/drift control, statistics"],
  ["platform: windows", "0078d6", "RubyInstaller / DevKit specifics"],
  ["platform: macos",  "999999", "macOS / arm64 specifics"],
  ["ci",               "2088ff", "GitHub Actions workflows"]
].freeze

if ARGV.include?("--list")
  LABELS.each { |n, c, d| puts format("%-20s #%s  %s", n, c, d) }
  exit
end

dry = ARGV.include?("--dry-run")
repo = ENV["REPO"] ? ["--repo", ENV["REPO"]] : []
LABELS.each do |name, color, desc|
  cmd = ["gh", "label", "create", name, "--color", color, "--description", desc, "--force", *repo]
  if dry
    puts cmd.map { _1.include?(" ") ? %("#{_1}") : _1 }.join(" ")
  else
    system(*cmd) or warn "failed: #{name}"
  end
end
