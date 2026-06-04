// CHECK: foo(0xF0, 0x3C) == 0xCC && foo(5, 5) == 0
int foo(int a, int b) {
    return a ^ b;
}
