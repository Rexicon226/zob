// Struct passed by value: callee mutates its copy; caller's struct is unchanged.
// CHECK: foo()==140
struct P { int x; int y; };
int sum(struct P p) { p.x = p.x + 100; return p.x + p.y; }
int foo(void) {
    struct P p; p.x = 10; p.y = 20;
    int s = sum(p);     // callee sees 110 + 20 = 130
    return s + p.x;     // caller's p.x still 10  => 140
}
