// CHECK: foo()==42
void set(int *p, int v) { *p = v; }
int foo(void) {
    int a[2];
    set(&a[1], 42);
    return a[1];
}
