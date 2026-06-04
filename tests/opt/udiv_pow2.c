// EXPECT: foo(80) == 10 && foo(7) == 0
// ASM: srl
// ASM-NOT: div
unsigned foo(unsigned x) {
    return x / 8u;
}
