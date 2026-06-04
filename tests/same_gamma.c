// EXPECT: foo(1) == 5 && foo(0) == 5
int foo(int c) {
    if (c) {
        return 5;
    } else {
        return 5;
    }
}
