// EXPECT: foo() == 14
// ASM: li {{.*}}, 14
// ASM-NOT: add
// ASM-NOT: mul
int foo(void) {
    return 2 + 3 * 4;
}
