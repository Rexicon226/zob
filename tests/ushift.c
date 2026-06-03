// CHECK: foo(-2) == 2147483647 && foo(8) == 4
int foo(int n) {
    unsigned u = n;
    return u >> 1;
}
