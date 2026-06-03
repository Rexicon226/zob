// CHECK: foo()==42
struct N { int v; struct N *next; };
int foo(void) {
    struct N b; b.v = 42;
    struct N a; a.v = 7; a.next = &b;
    return a.next->v;
}
