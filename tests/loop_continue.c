// EXPECT: foo(5) == 8 && foo(0) == 0
int foo(int n) {
    int s = 0;
    for (int i = 0; i < n; i = i + 1) {
        if (i == 2) continue;
        s = s + i;
    }
    return s;
}
