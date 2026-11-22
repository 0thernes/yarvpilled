# frozen_string_literal: true

# Tasks (`rake -T`):
#   rake compile   build the ruby.h C extension (+ x86-64 asm, + Rust kernel if cargo is present)
#   rake test      minitest suite (native backends are skipped if the extension is absent)
#   rake smoke     short headless run, prints stats
#   rake bench     multi-tier benchmark -> out/bench.md
#   rake control   selection vs drift experiment -> out/control.md
#   rake video     render out/yarvpilled.mp4 + gif + stills (needs ffmpeg)
#   rake clean     remove build products
#
# Environment:
#   YP_STRICT=1        fail `rake compile` instead of falling back to pure Ruby (used by CI)
#   YP_NO_RUST=1       skip the Rust kernel even if cargo is installed
#   YARVPILLED_PURE=1  ignore a compiled extension at runtime and use pure Ruby

require "rake/testtask"
require "rbconfig"
require "fileutils"

ROOT = __dir__
RUBY = RbConfig.ruby
WINDOWS = RbConfig::CONFIG["host_os"].match?(/mswin|mingw|cygwin/)
RUST_DIR = File.join(ROOT, "ext/yarvpilled_rust")
RUST_LIB = File.join(RUST_DIR, "target/release/libyarvpilled_rust.a")
BUILD = File.join(ROOT, "tmp/build")
SO_GLOB = File.join(ROOT, "lib/yarvpilled/yarvpilled_native.{so,bundle,dll}")
STRICT = ENV["YP_STRICT"] == "1"

def yjit_flag
  ok = system(RUBY, "--yjit", "-e", "exit(defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled? ? 0 : 1)", err: File::NULL)
  ok ? ["--yjit"] : []
end

def tool?(cmd) = system("#{cmd} --version", out: File::NULL, err: File::NULL)

# RubyInstaller ships MSYS2/DevKit; put its gcc/make on PATH like `ridk enable`.
if WINDOWS
  begin
    require "ruby_installer/runtime"
    RubyInstaller::Runtime.enable_msys_apps
  rescue LoadError, StandardError => e
    warn "RubyInstaller DevKit not available (#{e.class}); the C extension may not build"
  end
end

desc "Build the Rust world kernel (staticlib, C ABI) if cargo is available"
task :rust do
  if ENV["YP_NO_RUST"] == "1" || WINDOWS
    puts "skipping Rust kernel#{' (Windows: not wired up)' if WINDOWS}"
  elsif tool?("cargo")
    Dir.chdir(RUST_DIR) { sh "cargo build --release --quiet" }
  else
    puts "cargo not found: building without the :rust backend"
  end
end

desc "Compile the ruby.h C extension (+asm, +Rust) into lib/yarvpilled/; falls back to pure Ruby on failure"
task compile: :rust do
  FileUtils.rm_rf(BUILD)
  FileUtils.mkdir_p(BUILD)
  Dir.glob(SO_GLOB).each { FileUtils.rm_f(_1) }
  begin
    Dir.chdir(BUILD) do
      env = File.exist?(RUST_LIB) && !WINDOWS && ENV["YP_NO_RUST"] != "1" ? { "YP_RUST_LIB" => RUST_LIB } : {}
      sh env, RUBY, File.join(ROOT, "ext/yarvpilled_native/extconf.rb")
      sh ENV.fetch("MAKE", "make")
      so = Dir["yarvpilled_native.{so,bundle,dll}"].first or raise "no extension produced"
      FileUtils.cp(so, File.join(ROOT, "lib/yarvpilled/"))
      puts "built #{so}"
    end
  rescue StandardError => e
    raise if STRICT

    warn "\nC extension build failed (#{e.message.lines.first&.strip})."
    warn "Continuing with the pure-Ruby world and rasterizer: everything still runs, just slower."
  end
end

Rake::TestTask.new(:test) do |t|
  t.libs << "lib" << "test"
  t.test_files = FileList["test/test_*.rb"]
  t.warning = false
end

desc "Short headless simulation run (300 ticks)"
task :smoke do
  sh RUBY, File.join(ROOT, "yarv_brain.rb"), "--version"
  sh RUBY, File.join(ROOT, "yarv_brain.rb"), "--headless", "--ticks=300", "--out=#{File.join(ROOT, 'tmp/smoke')}"
end

desc "Benchmark every available tier (REPEATS=5 TICKS=2000) -> out/bench.md"
task :bench do
  sh RUBY, File.join(ROOT, "yarv_brain.rb"), "--bench", "--ticks=#{ENV.fetch('TICKS', '2000')}",
     "--repeats=#{ENV.fetch('REPEATS', '5')}"
end

desc "Selection vs random-drift control (REPLICATES=8 TICKS=4000) -> out/control.md"
task :control do
  sh RUBY, *yjit_flag, File.join(ROOT, "yarv_brain.rb"), "--control",
     "--replicates=#{ENV.fetch('REPLICATES', '8')}", "--ticks=#{ENV.fetch('TICKS', '4000')}"
end

desc "Render out/yarvpilled.mp4 + gif + stills + run log (needs ffmpeg)"
task :video do
  sh RUBY, *yjit_flag, File.join(ROOT, "yarv_brain.rb"), "--video"
end

desc "Remove build products (tmp/, compiled extension, Rust target/)"
task :clean do
  FileUtils.rm_rf(File.join(ROOT, "tmp"))
  FileUtils.rm_rf(File.join(RUST_DIR, "target"))
  Dir.glob(SO_GLOB).each { FileUtils.rm_f(_1) }
end

task default: %i[compile test]
