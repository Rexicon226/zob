// CHECK: foo(7) == 7 && foo(0) == 0
int foo(int n) {
    int i = 0;
    while (1) {
        if (i == n) break;
        i = i + 1;
    }
    return i;
}
