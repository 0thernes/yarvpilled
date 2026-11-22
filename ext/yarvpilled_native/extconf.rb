# frozen_string_literal: true
require "mkmf"
# ruby.h C API + libm only. No third-party libraries.
have_library("m", "cos")
$CFLAGS << " -O3 -std=c99 -Wall -Wextra -Wno-unused-parameter"
create_makefile("yarvpilled/yarvpilled_native")
