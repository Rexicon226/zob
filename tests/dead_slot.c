// CHECK: foo(5) == 10
int foo(int n) {
    int s = 0;
    int junk = 0;
    for (int i = 0; i < n; i = i + 1) {
        s = s + i;
        junk = junk + 7;
    }
    return s;
}
