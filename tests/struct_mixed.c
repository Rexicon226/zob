// Mixed-width fields exercise field offsets + sub-word load/store widths.
// CHECK: foo()==1007
struct M { char c; int n; };
int foo(void) {
    struct M m;
    m.c = 7;
    m.n = 1000;
    return m.c + m.n;
}
