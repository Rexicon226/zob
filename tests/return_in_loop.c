// EXPECT: foo(10)==4 && foo(0)==0 && foo(16)==4
int foo(int n) {
    for (int i = 0; i < 100; i = i + 1) {
        if (i * i >= n) return i;
    }
    return -1;
}
