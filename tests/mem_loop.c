// CHECK: foo(buf, 5) == 4 && buf[0] == 4
int foo(int *p, int n) {
    int i = 0;
    while (i < n) {
        *p = i;
        i = i + 1;
    }
    return *p;
}
