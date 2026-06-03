typedef unsigned long ulong;
typedef unsigned int uint;
typedef unsigned char uchar;

typedef union {
    uchar bytes[32];
    ulong limbs[4];
} fd_uint256_t;

void
fd_ulong_add_carry4( ulong *l, uchar *h, ulong a0, ulong a1, ulong a2, uchar a3 ) {
  ulong r0 = a0 + a1;
  uchar c0 = r0 < a0;

  ulong r1 = a2 + a3;
  uchar c1 = r1 < a2;

  *l = r0 + r1;
  *h = (uchar)((*l < r0) + c0 + c1);
}

fd_uint256_t *
fd_uint256_add(fd_uint256_t *       r,
               fd_uint256_t const * a,
               fd_uint256_t const * b ) {
  uchar c0;
  fd_ulong_add_carry4( &r->limbs[0], &c0, a->limbs[0], b->limbs[0], 0, 0 );
  fd_ulong_add_carry4( &r->limbs[1], &c0, a->limbs[1], b->limbs[1], 0, c0 );
  fd_ulong_add_carry4( &r->limbs[2], &c0, a->limbs[2], b->limbs[2], 0, c0 );
  fd_ulong_add_carry4( &r->limbs[3], &c0, a->limbs[3], b->limbs[3], 0, c0 );
  return r;
}