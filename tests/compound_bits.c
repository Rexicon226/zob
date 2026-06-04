// CHECK: foo(0xFF) == 0x28
int foo(int x) {
    x &= 0x3C;
    x |= 0x80;
    x ^= 0xA8;
    x <<= 2;  
    x >>= 1;  
    return x;
}
