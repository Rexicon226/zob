// CHECK: foo()==198
int foo(void) {
    char b[4];
    b[0] = 65; b[1] = 66; b[2] = 67; b[3] = 0;
    return b[0] + b[1] + b[2];
}
