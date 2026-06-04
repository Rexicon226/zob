// CHECK: foo(5) == 25
int foo(int n) {
    int a[2];
    a[0] = n;
    a[1] = n + 100;
    a[0] = n * 2;
    int x = a[0];
    int y = x + n;
    a[1] = y;
    return a[0] + a[1]; // 10 + 15 = 25
}
