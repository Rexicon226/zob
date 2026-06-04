// EXPECT: foo()==42
union U { int i; int j; };
int foo(void) {
    union U u;
    u.i = 42;
    return u.j;
}
