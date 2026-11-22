# frozen_string_literal: true

require "rake/testtask"
require "fileutils"

ROOT = __dir__
RUST_DIR = File.join(ROOT, "ext/yarvpilled_rust")
RUST_LIB = File.join(RUST_DIR, "target/release/libyarvpilled_rust.a")

desc "Build the Rust world kernel (staticlib, C ABI) if cargo is available"
task :rust do
  if system("cargo --version > /dev/null 2>&1")
    Dir.chdir(RUST_DIR) { sh "cargo build --release --quiet" }
  else
    warn "cargo not found: building without the :rust backend"
  end
end

desc "Compile the ruby.h C extension (+asm, +Rust) into lib/yarvpilled/"
task compile: :rust do
  build = File.join(ROOT, "tmp/build")
  FileUtils.rm_rf(build)
  FileUtils.mkdir_p(build)
  Dir.chdir(build) do
    env = File.exist?(RUST_LIB) ? { "YP_RUST_LIB" => RUST_LIB } : {}
    sh env, "ruby #{File.join(ROOT, 'ext/yarvpilled_native/extconf.rb')}"
    sh "make -s"
    so = Dir["yarvpilled_native.{so,bundle}"].first
    FileUtils.cp(so, File.join(ROOT, "lib/yarvpilled/"))
  end
end

Rake::TestTask.new(:test) do |t|
  t.libs << "lib" << "test"
  t.test_files = FileList["test/test_*.rb"]
  t.warning = false
end

task default: %i[compile test]
