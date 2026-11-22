# frozen_string_literal: true

# Tasks (`rake -T`):
#   rake compile   build the ruby.h C extension (+ x86-64 asm, + Rust kernel if cargo is present)
#   rake test      minitest suite (native backends are skipped if the extension is absent)
#   rake smoke     short headless run, prints stats
#   rake bench     multi-tier benchmark -> out/bench.md
#   rake control   selection vs drift experiment -> out/control.md
#   rake video     render out/yarvpilled.mp4 + gif + stills (needs ffmpeg)
#   rake gem       build pkg/yarvpilled-VERSION.gem
#   rake site      build the GitHub Pages demo into _site/ (replay of a real run)
#   rake labels    create/update GitHub issue labels via gh (DRY=1 to print only)
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

desc "Build pkg/yarvpilled-VERSION.gem (C ext compiles on install; Rust backend is repo-only)"
task :gem do
  FileUtils.mkdir_p(File.join(ROOT, "pkg"))
  Dir.chdir(ROOT) { sh "gem", "build", "yarvpilled.gemspec", "--output", "pkg/yarvpilled-#{File.read('VERSION').strip}.gem" }
end

desc "Build the GitHub Pages demo into _site/ (TICKS=900)"
task :site do
  sh RUBY, *yjit_flag, File.join(ROOT, "tools/build_site.rb"), File.join(ROOT, "_site"), "--ticks=#{ENV.fetch('TICKS', '900')}"
end

desc "Create/update GitHub issue labels with gh (DRY=1 prints the commands)"
task :labels do
  sh RUBY, File.join(ROOT, "tools/labels.rb"), *(ENV["DRY"] == "1" ? ["--dry-run"] : [])
end

desc "Remove build products (tmp/, _site/, pkg/, compiled extension, Rust target/)"
task :clean do
  FileUtils.rm_rf(File.join(ROOT, "tmp"))
  FileUtils.rm_rf(File.join(ROOT, "_site"))
  FileUtils.rm_rf(File.join(ROOT, "pkg"))
  FileUtils.rm_rf(File.join(RUST_DIR, "target"))
  Dir.glob(SO_GLOB).each { FileUtils.rm_f(_1) }
end

desc "Run the whole test suite against an ASan+UBSan build of the C extension (Linux), then rebuild normally"
task :sanitize do
  abort "rake sanitize needs Linux + gcc" unless RbConfig::CONFIG["host_os"].include?("linux")
  cc = ENV.fetch("CC", "gcc")
  rt = %w[libasan.so libubsan.so].map { `#{cc} -print-file-name=#{_1}`.strip }
  san_build = File.join(ROOT, "tmp/sanitize")
  FileUtils.rm_rf(san_build)
  FileUtils.mkdir_p(san_build)
  ok = false
  begin
    Dir.chdir(san_build) do
      env = { "YP_SANITIZE" => "1" }
      env["YP_RUST_LIB"] = RUST_LIB if File.exist?(RUST_LIB)
      sh env, RUBY, File.join(ROOT, "ext/yarvpilled_native/extconf.rb")
      sh "make"
      Dir.glob(SO_GLOB).each { FileUtils.rm_f(_1) }
      FileUtils.cp("yarvpilled_native.so", File.join(ROOT, "lib/yarvpilled/"))
    end
    # use_sigaltstack=0: Ruby installs its own alternate signal stack; ASan's
    # conflicts with it on thread exit ("failed to deallocate").
    env = { "LD_PRELOAD" => rt.join(" "), "ASAN_OPTIONS" => "detect_leaks=0:use_sigaltstack=0:abort_on_error=1",
            "UBSAN_OPTIONS" => "halt_on_error=1:print_stacktrace=1" }
    ok = system(env, RUBY, "-Ilib", "-Itest", "-e", 'Dir["test/test_*.rb"].sort.each { require "./#{_1}" }', chdir: ROOT)
  ensure
    Rake::Task[:compile].invoke
  end
  abort "sanitizer run failed" unless ok
  puts "sanitizer run: all tests passed under ASan + UBSan"
end

task default: %i[compile test]
