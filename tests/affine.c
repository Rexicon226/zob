// Should get compiled down into `s = x * 10`.
// EXPECT: foo(3) == 30 && foo(0) == 0 && foo(-2) == -20
int foo(int x) {
    int s = 0;
    for (int i = 0; i < 10; i = i + 1) {
        s = s + x;
    }
    return s;
}
