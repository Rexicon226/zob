// EXPECT: foo(buf) == 7
int foo(int *p) {
    p[0] = 3;
    p[1] = 4;
    int x = *p++;
    int y = *p;
    return x + y;
}
