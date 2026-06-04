// EXPECT: foo(1)==5 && foo(9)==-1
int foo(int x) {
    int r = -1;
    switch (x) {
        case 1: r = 5; break;
        case 2: r = 6; break;
    }
    return r;
}
