// EXPECT: foo(1) == 10 && foo(0) == 20
int foo(int y) {
    if (y) return 10;
    return 20;
}
