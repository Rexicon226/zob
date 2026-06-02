// CHECK: foo(5) == 10 && foo(1) == 0 && foo(0) == 0
int foo(int n) {
    int s = 0;
    for (int i = 0; i < n; i = i + 1) {
        s = s + i;
    }
    return s;
}
