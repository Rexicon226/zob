// CHECK: (foo(buf), buf[0]) == 20 && foo(buf) == 10
int foo(int *x) {
    *x = 10;
    int a = *x;
    *x = 20;
    return a;
}
