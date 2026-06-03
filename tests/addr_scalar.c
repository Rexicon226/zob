// CHECK: foo(10)==35
void add(int *p, int v) { *p = *p + v; }
int foo(int x) {
    int s = 0;
    add(&s, x);
    add(&s, 25);
    add(&x, 100); // doesn't affect the result
    return s;
}
