// CHECK: foo(1, buf) == 1 && foo(0, buf) == 2
int foo(int c, int *x) {
    if (c) {
        *x = 1;
    } else {
        *x = 2;
    }
    return *x;
}
