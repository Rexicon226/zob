// Array of structs, indexed and member-accessed; also nested via pointer walk.
// CHECK: foo()==303
struct V { int lo; int hi; };
int foo(void) {
    struct V v[3];
    for (int i = 0; i < 3; i = i + 1) { v[i].lo = i; v[i].hi = i * 100; }
    int s = 0;
    for (int i = 0; i < 3; i = i + 1) s = s + v[i].lo + v[i].hi;
    return s;
}
