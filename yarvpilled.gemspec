# frozen_string_literal: true

require_relative "lib/yarvpilled/version"

Gem::Specification.new do |s|
  s.name = "yarvpilled"
  s.version = Yarvpilled::VERSION
  s.authors = ["0thernes"]
  s.email = ["0_0@0thernes.art"]
  s.summary = "A-Life world where every creature's brain is a live YARV instruction sequence."
  s.description = <<~DESC
    Zero-model artificial life in pure CRuby: each creature thinks by executing a Ruby method compiled
    with RubyVM::InstructionSequence, genomes mutate on reproduction, and TracePoint hot-swaps live
    methods. The world loop runs on bit-identical pure-Ruby, C, Rust or x86-64 asm backends.
    Includes a terminal mode, a browser mode, video rendering, a benchmark and a selection-vs-drift control.
  DESC
  s.homepage = "https://github.com/0thernes/yarvpilled"
  s.license = "MIT"
  s.required_ruby_version = ">= 3.3"
  s.metadata = {
    "homepage_uri" => s.homepage,
    "source_code_uri" => s.homepage,
    "changelog_uri" => "#{s.homepage}/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "#{s.homepage}/issues",
    "rubygems_mfa_required" => "true"
  }

  # Lean package: code, C/asm sources, the browser page and the top-level docs. No media, tests or Rust.
  s.files = Dir["lib/**/*.rb", "lib/yarvpilled/data/*", "ext/yarvpilled_native/*.{c,h,S,rb}",
                "public/index.html", "exe/*", "yarv_brain.rb", "server.rb", "tools/build_site.rb",
                "README.md", "CHANGELOG.md", "LICENSE", "VERSION"]
  s.bindir = "exe"
  s.executables = ["yarvpilled"]
  s.require_paths = ["lib"]
  s.extensions = ["ext/yarvpilled_native/extconf.rb"]
end
