// EXPECT: foo() == 1
int foo(void) {
    unsigned x = 3000000000u;
    return (x % 100u) == 0u;
}
