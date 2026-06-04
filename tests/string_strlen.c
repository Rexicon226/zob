// CHECK: foo() == 5
int foo(void) {
    char *s = "hello";
    int n = 0;
    while (s[n]) n++;
    return n;
}
