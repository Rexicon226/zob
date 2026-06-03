// CHECK: foo(6)==16 && foo(0)==0 && foo(81)==99
int foo(int n) {
    for (int i = 0; i < 10; i = i + 1)
        for (int j = 0; j < 10; j = j + 1)
            if (i * j == n) return i * 10 + j;
    return -1;
}
