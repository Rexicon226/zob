// EXPECT: foo()==683
struct P { int x; int y; };
struct P dbl(struct P p) { p.x = p.x * 2; p.y = p.y * 2; return p; }
int foo(void) {
    struct P a; a.x = 3; a.y = 4;
    struct P b = dbl(a);          // {6, 8}
    return b.x * 100 + b.y * 10 + a.x;   // 600 + 80 + 3
}
