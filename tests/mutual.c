// EXPECT: foo(4) == 1 && foo(7) == 0 && foo(0) == 1
int is_odd(int n);
int is_even(int n) {
    if (n == 0) return 1;
    return is_odd(n - 1);
}
int is_odd(int n) {
    if (n == 0) return 0;
    return is_even(n - 1);
}
int foo(int n) {
    return is_even(n);
}
