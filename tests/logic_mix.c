// CHECK: foo(5) == 1 && foo(15) == 0 && foo(-1) == 0
int foo(int x) {
    return x > 0 && x < 10;
}
