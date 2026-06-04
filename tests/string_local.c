// EXPECT: foo(0) == 'h' && foo(1) == 'i' && foo(2) == 0 && foo(7) == 0
int foo(int i) {
    char buf[8] = "hi"; // bytes past "hi\0" must be zero
    return buf[i];
}
