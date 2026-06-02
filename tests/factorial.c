// CHECK: foo(5) == 120 && foo(0) == 1 && foo(1) == 1
int foo(int n) {
    int f = 1;
    for (int i = 1; i < n + 1; i = i + 1) {
        f = f * i;
    }
    return f;
}
