// CHECK: foo(5) == 14
int foo(int n) {
    int a = n;
    int *p = &a;
    a++;
    ++a;
    return *p + a;
}
