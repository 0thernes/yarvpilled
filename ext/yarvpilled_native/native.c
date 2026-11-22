/* Entry point for yarvpilled/yarvpilled_native.so */
#include <ruby.h>
void Init_yarvpilled_world(VALUE);
void Init_yarvpilled_raster(VALUE);

void Init_yarvpilled_native(void) {
  VALUE top = rb_define_module("Yarvpilled");
  VALUE native = rb_define_module_under(top, "Native");
  rb_define_const(native, "BUILT_WITH", rb_str_new_cstr("ruby.h C API, libm"));
  Init_yarvpilled_world(native);
  Init_yarvpilled_raster(native);
}
