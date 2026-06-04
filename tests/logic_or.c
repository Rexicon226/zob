// CHECK: foo(0, 0) == 0 && foo(0, 5) == 1 && foo(2, 0) == 1
int foo(int a, int b) {
    return a || b;
}
