// CHECK: foo(buf, 5) == 42 && buf[0] == 42
int foo(int *p, int n) {
    *p = 42;
    while (n > 0) {
        n = n - 1;
    }
    return *p;
}
