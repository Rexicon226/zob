// EXPECT: foo(3,4)==34 && foo(7,1)==71
struct Point { int x; int y; };
int foo(int a, int b) {
    struct Point p;
    p.x = a;
    p.y = b;
    return p.x * 10 + p.y;
}
