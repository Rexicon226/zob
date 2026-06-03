// CHECK: foo(3)==9 && foo(10)==30
int foo(int n) {
    int a[4];
    a[0] = n;
    a[1] = n + 1;
    a[2] = a[0] + a[1];
    return a[2] + n - 1;
}
