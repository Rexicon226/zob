// CHECK: foo(-1) == 1 && foo(3) == 0 && foo(9) == 1
int foo(int n) {
    unsigned u = n;
    return u > 5;
}
