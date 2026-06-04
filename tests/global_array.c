// CHECK: foo(10)==53
int y[3];
int sum(int *p) {
    return p[0] + p[1] + p[2];
}
int foo(int x) {
    y[0] = x;
    y[1] = x + x;
    y[2] = x + x + 3;
    return sum(y);
}