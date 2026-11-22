/* Generated once by tools/gen_trig.c from glibc cos/sin(2*pi*k/64) (correctly rounded).
 * Literal bit patterns, so every platform and backend uses identical directions
 * regardless of its libm. lib/yarvpilled/trig_table.rb holds the same bits. */
#ifndef YP_TRIG_TABLE_H
#define YP_TRIG_TABLE_H
#include <stdint.h>
static const uint64_t YP_COS_BITS[64] = {
  0x3ff0000000000000ULL,  0x3fefd88da3d12526ULL,  0x3fef6297cff75cb0ULL,  0x3fee9f4156c62ddaULL,
  0x3fed906bcf328d46ULL,  0x3fec38b2f180bdb1ULL,  0x3fea9b66290ea1a3ULL,  0x3fe8bc806b151741ULL,
  0x3fe6a09e667f3bcdULL,  0x3fe44cf325091dd6ULL,  0x3fe1c73b39ae68c9ULL,  0x3fde2b5d3806f63eULL,
  0x3fd87de2a6aea964ULL,  0x3fd294062ed59f05ULL,  0x3fc8f8b83c69a60dULL,  0x3fb917a6bc29b438ULL,
  0x3c91a62633145c07ULL,  0xbfb917a6bc29b42fULL,  0xbfc8f8b83c69a608ULL,  0xbfd294062ed59f02ULL,
  0xbfd87de2a6aea962ULL,  0xbfde2b5d3806f63cULL,  0xbfe1c73b39ae68c6ULL,  0xbfe44cf325091dd5ULL,
  0xbfe6a09e667f3bccULL,  0xbfe8bc806b151741ULL,  0xbfea9b66290ea1a4ULL,  0xbfec38b2f180bdb0ULL,
  0xbfed906bcf328d46ULL,  0xbfee9f4156c62ddaULL,  0xbfef6297cff75cb0ULL,  0xbfefd88da3d12525ULL,
  0xbff0000000000000ULL,  0xbfefd88da3d12526ULL,  0xbfef6297cff75cb0ULL,  0xbfee9f4156c62ddbULL,
  0xbfed906bcf328d47ULL,  0xbfec38b2f180bdb1ULL,  0xbfea9b66290ea1a5ULL,  0xbfe8bc806b151742ULL,
  0xbfe6a09e667f3bceULL,  0xbfe44cf325091ddaULL,  0xbfe1c73b39ae68c8ULL,  0xbfde2b5d3806f63fULL,
  0xbfd87de2a6aea96dULL,  0xbfd294062ed59f07ULL,  0xbfc8f8b83c69a619ULL,  0xbfb917a6bc29b421ULL,
  0xbcaa79394c9e8a0aULL,  0x3fb917a6bc29b407ULL,  0x3fc8f8b83c69a60cULL,  0x3fd294062ed59f00ULL,
  0x3fd87de2a6aea967ULL,  0x3fde2b5d3806f63aULL,  0x3fe1c73b39ae68c5ULL,  0x3fe44cf325091dd7ULL,
  0x3fe6a09e667f3bcbULL,  0x3fe8bc806b15173eULL,  0x3fea9b66290ea1a3ULL,  0x3fec38b2f180bdafULL,
  0x3fed906bcf328d44ULL,  0x3fee9f4156c62ddaULL,  0x3fef6297cff75cafULL,  0x3fefd88da3d12526ULL,
};
static const uint64_t YP_SIN_BITS[64] = {
  0x0000000000000000ULL,  0x3fb917a6bc29b42cULL,  0x3fc8f8b83c69a60aULL,  0x3fd294062ed59f05ULL,
  0x3fd87de2a6aea963ULL,  0x3fde2b5d3806f63bULL,  0x3fe1c73b39ae68c8ULL,  0x3fe44cf325091dd6ULL,
  0x3fe6a09e667f3bccULL,  0x3fe8bc806b151741ULL,  0x3fea9b66290ea1a3ULL,  0x3fec38b2f180bdb0ULL,
  0x3fed906bcf328d46ULL,  0x3fee9f4156c62ddbULL,  0x3fef6297cff75cb0ULL,  0x3fefd88da3d12525ULL,
  0x3ff0000000000000ULL,  0x3fefd88da3d12526ULL,  0x3fef6297cff75cb0ULL,  0x3fee9f4156c62ddbULL,
  0x3fed906bcf328d46ULL,  0x3fec38b2f180bdb1ULL,  0x3fea9b66290ea1a5ULL,  0x3fe8bc806b151742ULL,
  0x3fe6a09e667f3bcdULL,  0x3fe44cf325091dd6ULL,  0x3fe1c73b39ae68c8ULL,  0x3fde2b5d3806f63fULL,
  0x3fd87de2a6aea965ULL,  0x3fd294062ed59f06ULL,  0x3fc8f8b83c69a617ULL,  0x3fb917a6bc29b43cULL,
  0x3ca1a62633145c07ULL,  0xbfb917a6bc29b42bULL,  0xbfc8f8b83c69a60eULL,  0xbfd294062ed59f01ULL,
  0xbfd87de2a6aea961ULL,  0xbfde2b5d3806f63bULL,  0xbfe1c73b39ae68c6ULL,  0xbfe44cf325091dd4ULL,
  0xbfe6a09e667f3bccULL,  0xbfe8bc806b15173eULL,  0xbfea9b66290ea1a3ULL,  0xbfec38b2f180bdb0ULL,
  0xbfed906bcf328d44ULL,  0xbfee9f4156c62ddaULL,  0xbfef6297cff75cafULL,  0xbfefd88da3d12526ULL,
  0xbff0000000000000ULL,  0xbfefd88da3d12526ULL,  0xbfef6297cff75cb0ULL,  0xbfee9f4156c62ddbULL,
  0xbfed906bcf328d45ULL,  0xbfec38b2f180bdb1ULL,  0xbfea9b66290ea1a5ULL,  0xbfe8bc806b151740ULL,
  0xbfe6a09e667f3bceULL,  0xbfe44cf325091ddaULL,  0xbfe1c73b39ae68c8ULL,  0xbfde2b5d3806f640ULL,
  0xbfd87de2a6aea96eULL,  0xbfd294062ed59f08ULL,  0xbfc8f8b83c69a61bULL,  0xbfb917a6bc29b425ULL,
};
#endif
