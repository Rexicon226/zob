// EXPECT: foo()==79
struct P { int x; int y; };
int foo(void) {
    struct P p = (struct P){7, 8};
    return p.x * 10 + p.y + (struct P){5, 9}.x - (struct P){0, 4}.y;  // 78 + 5 - 4
}
