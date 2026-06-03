// CHECK: foo(0) == 1
int foo(int n) {
    long a = 100000 + n;
    long b = a * a;
    return b == 10000000000L;
}
