// CHECK: foo(5) == 5 && foo(0) == 0 && foo(10) == 10
int inc(int x) {
    return x + 1;
}
int foo(int n) {
    int s = 0;
    for (int i = 0; i < n; i = i + 1) {
        s = inc(s);
    }
    return s;
}
