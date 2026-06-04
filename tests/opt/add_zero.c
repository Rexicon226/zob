// EXPECT: foo(5) == 5 && foo(-9) == -9
// ASM-NOT: add
int foo(int x) {
    return x + 0;
}
