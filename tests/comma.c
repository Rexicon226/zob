// EXPECT: foo(5) == 7
int foo(int x) {
    int a = 0;
    int y = (a = x, a + 2);
    return y;
}
