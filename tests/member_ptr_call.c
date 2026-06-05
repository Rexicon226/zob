// EXPECT: foo()==52
typedef struct { int value; int (*foo)(int); } S;

int callback(int x) {
    return x + 10;
}

int bar(S *s) {
    return s->foo(s->value);
}

int foo(void) {
    S s = { .value = 42, .foo = callback };
    return bar(&s);
}
