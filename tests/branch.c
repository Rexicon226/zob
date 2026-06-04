// EXPECT: foo(0, buf) == 20 && foo(1, buf) == 10 && buf[0] == 30
int foo(int y, int *x) {
    if (y) {
        *x = 30;
        return 10;
    } else {
        return 20;
    }
}
