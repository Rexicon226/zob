// EXPECT: foo()==527
struct F { unsigned a : 3; unsigned b : 5; int c : 4; };
int foo(void) {
    struct F f;
    f.a = 5;
    f.b = 20;
    f.c = -3;
    return f.a * 100 + f.b + (f.c + 10);   // 500 + 20 + 7 = 527
}
