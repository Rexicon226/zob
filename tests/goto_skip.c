// EXPECT: foo(5)==6 && foo(0)==1
int foo(int x) {
    int r = 1;
    goto skip;
    r = 999;
skip:
    r = r + x;
    return r;
}
