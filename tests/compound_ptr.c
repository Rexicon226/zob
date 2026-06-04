// CHECK: foo() == 30
int foo(void) {
    int a[5];
    a[0] = 10;
    a[1] = 20;
    a[2] = 30;
    a[3] = 40;
    a[4] = 50;
    int *p = a;
    p += 2;
    return *p;
}
