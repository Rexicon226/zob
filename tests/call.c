// CHECK: foo(5) == 15 && foo(0) == 10
int add(int a, int b) {
    return a + b;
}
int foo(int n) {
    return add(n, 10);
}
