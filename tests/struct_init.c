// Struct initializer list and a partial (default-zeroed) initializer.
// EXPECT: foo()==63
struct Q { int a; int b; int c; };
int foo(void) {
    struct Q q = {10, 20, 30};
    struct Q r = {3};            // b, c default to 0
    return q.a + q.b + q.c + r.a;  // 60 + 3
}
