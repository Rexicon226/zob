// Designated initializers, out of order, with a defaulted field.
// CHECK: foo()==250
struct P { int x; int y; int z; };
int foo(void) {
    struct P p = { .y = 5, .x = 2 };
    return p.x*100 + p.y*10 + p.z;
}
