// EXPECT: foo(1) == 10 && foo(0) == 20 && foo(-3) == 10
int foo(int c) {
    return c ? 10 : 20;
}
