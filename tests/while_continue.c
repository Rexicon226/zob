// CHECK: foo(5) == 12 && foo(0) == 0
int foo(int n) {
    int s = 0;
    int i = 0;
    while (i < n) {
        i = i + 1;
        if (i == 3) continue;
        s = s + i;
    }
    return s;
}
