// EXPECT: foo(5)==50 && foo(-1)==-1 && foo(0)==0
int foo(int x) {
    int r = 0;
    if (x < 0) { r = -1; goto done; }
    r = x * 10;
done:
    return r;
}
