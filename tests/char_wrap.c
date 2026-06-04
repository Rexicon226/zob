// EXPECT: foo(200) == 200 && foo(5) == 5 && foo(-1) == 255
int foo(int n) {
    char c = n;
    return c;
}
