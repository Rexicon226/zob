// EXPECT: foo(0) == 'a' && foo(1) == 'b' && foo(2) == 'c'
char *names[] = {"abc", "bcd", "cde"};
int foo(int i) {
    return names[i][0];
}
