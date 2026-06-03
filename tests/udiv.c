// CHECK: foo(-2) == 2147483647 && foo(10) == 5
int foo(int n) {
    unsigned u = n;
    return u / 2;
}
