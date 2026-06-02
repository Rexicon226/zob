// CHECK: foo(1) == 10 && foo(0) == 20
int foo(int c) {
    int v = 0;
    if (c) {
        v = 10;
    } else {
        v = 20;
    }
    return v;
}
