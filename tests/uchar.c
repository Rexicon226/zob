// CHECK: foo(200) == 200 && foo(300) == 44 && foo(-1) == 255
int foo(int n) {
    unsigned char c = n;
    return c;
}
