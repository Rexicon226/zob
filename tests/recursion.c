// EXPECT: foo(5) == 120 && foo(3) == 6 && foo(0) == 1
int foo(int n) {
    if (n == 0) return 1;
    return n * foo(n - 1);
}
