// CHECK: foo(10) == 54
int foo(int n) {
    int a = n;
    int b = a++;
    int c = ++a;
    int d = a--;
    int e = --a;
    return b + c + d + e + a;
}
