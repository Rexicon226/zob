// CHECK: foo(3) == 3 && foo(1) == 1 && foo(0) == 0
int foo(int n) {
    int s = 0;
    for (int i = 0; i < n; i = i + 1) {
        for (int j = 0; j < n; j = j + 1) {
            if (j == 1) break;
            s = s + 1;
        }
    }
    return s;
}
