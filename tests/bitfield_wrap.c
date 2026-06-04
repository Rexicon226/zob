// Writing more than the field width truncates to the field's bits.
// EXPECT: foo()==5
struct F { unsigned a : 3; unsigned b : 3; };
int foo(void) {
    struct F f;
    f.a = 13;   // 13 & 7 == 5
    f.b = 0;
    return f.a;
}
