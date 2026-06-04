// EXPECT: foo(10, 10) == 100 && foo(0, 100) == 0 && foo(100, 0) == 0
int foo(int x, int y) {
    int s = 0;
    for (int i = 0; i < y; i = i + 1) {
        s = s + x;
    }
    return s;
}