// CHECK: foo(0)==12 && foo(1)==99
struct P { int x; int y; };
struct P pick(int c) {
    struct P p;
    if (c) { p.x = 9; p.y = 9; } else { p.x = 1; p.y = 2; }
    return p;
}
int foo(int c) {
    struct P r = pick(c);
    return r.x * 10 + r.y;
}
