// EXPECT: foo(0) == 'o' && foo(1) == 'k' && foo(2) == 0
char g[] = "ok";
int foo(int i) {
    return g[i];
}
