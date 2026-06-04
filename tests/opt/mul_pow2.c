// EXPECT: foo(5) == 40 && foo(-3) == -24
// ASM: sll
// ASM-NOT: mul
int foo(int x) {
    return x * 8;
}
