// EXPECT: foo()==6
int sum3(int *p) { return *p + *(p + 1) + p[2]; }
int foo(void) {
    int a[3];
    a[0] = 1; a[1] = 2; a[2] = 3;
    return sum3(&a[0]);
}
