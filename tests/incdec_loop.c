// CHECK: foo(5) == 10
int foo(int n) {
    int s = 0;
    for (int i = 0; i < n; i++) s = s + i; // 0+1+2+3+4 = 10
    return s;
}
