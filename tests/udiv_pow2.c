// EXPECT: foo(-16) == 268435455 && foo(80) == 5 && foo(0) == 0
int foo(int n) {
    unsigned u = n;
    return u / 16;
}
