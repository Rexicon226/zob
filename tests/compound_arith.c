// CHECK: foo(10) == 2
int foo(int x) {
    x += 5;  // 15
    x -= 2;  // 13
    x *= 3;  // 39
    x /= 2;  // 19
    x %= 17; // 2
    return x;
}
