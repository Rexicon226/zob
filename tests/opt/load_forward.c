// EXPECT: foo(5) == 25
// ASM-NOT: {{\bsw\b}}
// ASM-NOT: {{\blw\b}}
int foo(int x) {
    int a[1];
    a[0] = x * x;
    return a[0];
}
