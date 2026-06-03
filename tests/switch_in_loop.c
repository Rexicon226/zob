// CHECK: foo(6)==109 && foo(0)==0
int foo(int n) {
    int s = 0;
    for (int i = 0; i < n; i = i + 1) {
        switch (i) {
            case 2: s = s + 100; break;
            case 4: continue;
            default: s = s + i; break;
        }
    }
    return s;
}
