// EXPECT: foo(4) == 10 && foo(0) == 6
int sum4(int a, int b, int c, int d) {
    return a + b + c + d;
}
int foo(int n) {
    return sum4(n, 1, 2, 3);
}
