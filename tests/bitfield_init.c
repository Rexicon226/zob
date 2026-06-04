// EXPECT: foo()==286
struct F { unsigned a : 4; unsigned b : 4; unsigned c : 8; };
int foo(void) {
    struct F f = { 2, 8, 6 };
    return f.a * 100 + f.b * 10 + f.c;   // 200 + 80 + 6
}
