// CHECK: foo(10) == 3 && foo(2) == 1 && foo(0) == 0
int foo(int n) {
    int s = 0;
    for (int i = 0; i < n; i = i + 1) {
        if (i == 3) break;
        s = s + i;
    }
    return s;
}
