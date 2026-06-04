// EXPECT: foo(5)==10 && foo(1)==0 && foo(8)==28
int foo(int n) {
    int a[16];
    for (int i = 0; i < n; i = i + 1) a[i] = i;
    int s = 0;
    for (int i = 0; i < n; i = i + 1) s = s + a[i];
    return s;
}
