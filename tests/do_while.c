// CHECK: foo(3) == 6 && foo(0) == 1
int foo(int n) {
    int s = 0;
    int i = 0;
    do {
        i = i + 1;
        s = s + i;
    } while (i < n);
    return s;
}
