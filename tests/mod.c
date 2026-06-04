// CHECK: foo(17, 5) == 2 && foo(-17, 5) == -2 && foo(17, -5) == 2
int foo(int a, int b) {
    return a % b;
}
