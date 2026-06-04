// EXPECT: foo(0x1234) == 52 && foo(300) == 44 && foo(255) == 255
unsigned foo(unsigned n) {
    unsigned char c = n;
    return c & 0xFF;
}
