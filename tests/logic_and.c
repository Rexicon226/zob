// EXPECT: foo(1, 2) == 1 && foo(0, 2) == 0 && foo(3, 0) == 0
int foo(int a, int b) {
    return a && b;
}
