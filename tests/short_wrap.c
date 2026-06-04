// EXPECT: foo(40000) == -25536 && foo(7) == 7
int foo(int n) {
    short s = n;
    return s;
}
