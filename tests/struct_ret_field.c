// CHECK: foo()==9
struct P { int x; int y; };
struct P make(int a, int b) { struct P p; p.x = a; p.y = b; return p; }
int foo(void) { return make(4, 9).y; }
