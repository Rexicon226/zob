// EXPECT: foo(3) == 9 && foo(0) == 0 && foo(1) == 1
int foo(int n) {
    int s = 0;
    int i = 0;
    while (i < n) {
        int j = 0;
        while (j < n) {
            s = s + 1;
            j = j + 1;
        }
        i = i + 1;
    }
    return s;
}
