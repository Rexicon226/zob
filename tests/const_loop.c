// CHECK: foo() == 45
int foo() {
    int s = 0;
    for (int i = 0; i < 10; i = i + 1) {
        s = s + i;
    }
    return s;
}
