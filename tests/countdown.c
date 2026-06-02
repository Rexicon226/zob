// CHECK: foo(7) == 0 && foo(0) == 0
int foo(int n) {
    while (n > 0) {
        n = n - 1;
    }
    return n;
}
