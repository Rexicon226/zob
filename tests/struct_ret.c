// CHECK: foo()==73
struct P { int x; int y; };
struct P make(int a, int b) { struct P p; p.x = a; p.y = b; return p; }
int foo(void) {
    struct P r = make(7, 3);
    return r.x * 10 + r.y;   // 70 + 3
}
