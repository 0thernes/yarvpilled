# frozen_string_literal: true

require "mkmf"

# ruby.h C API + libm, plus two optional world-loop backends:
#   * hand-written x86-64 asm (crowd_x86_64.S) on x86_64 Linux/BSD
#   * a Rust staticlib (ext/yarvpilled_rust) if YP_RUST_LIB points at it
have_library("m", "cos")
$CFLAGS << " -O3 -std=c99 -Wall -Wextra -Wno-unused-parameter"

srcdir = File.expand_path(__dir__)
$srcs = %w[native.c world.c kernel_c.c raster.c].map { File.join(srcdir, _1) }
$objs = %w[native.o world.o kernel_c.o raster.o]

asm = RbConfig::CONFIG["host_cpu"] =~ /x86_64|amd64/ && RbConfig::CONFIG["host_os"] !~ /darwin|mswin|mingw/
if asm
  $objs << "crowd_x86_64.o"
else
  # Non-x86_64: the :asm backend transparently falls back to the C crowd scan.
  $defs << "-DYP_NO_ASM"
end

rust_lib = ENV["YP_RUST_LIB"]
if rust_lib && File.exist?(rust_lib)
  $defs << "-DYP_HAVE_RUST"
  $LOCAL_LIBS << " #{rust_lib} -lpthread -ldl"
  puts "linking Rust kernel: #{rust_lib}"
end

create_makefile("yarvpilled/yarvpilled_native")

if asm
  File.open("Makefile", "a") do |f|
    f.puts "\ncrowd_x86_64.o: #{File.join(srcdir, 'crowd_x86_64.S')}"
    f.puts "\t$(ECHO) assembling $(<F)"
    f.puts "\t$(Q) $(CC) $(INCFLAGS) $(CPPFLAGS) -fPIC -c $< -o $@"
  end
end
