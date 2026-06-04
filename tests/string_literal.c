// CHECK: foo(0) == 'h' && foo(1) == 'i' && foo(2) == 0
int foo(int i) {
    char *s = "hi";
    return s[i];
}
