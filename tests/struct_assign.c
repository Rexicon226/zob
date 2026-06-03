// Struct assignment copies all members by value.
// CHECK: foo()==12
struct P { int x; int y; };
int foo(void) {
    struct P a; a.x = 1; a.y = 2;
    struct P b; b.x = 0; b.y = 0;
    b = a;
    return b.x*10 + b.y;
}
