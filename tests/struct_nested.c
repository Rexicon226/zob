// EXPECT: foo()==123
struct Inner { int a; int b; };
struct Outer { struct Inner in; int c; };
int foo(void) {
    struct Outer o;
    o.in.a = 1; o.in.b = 2; o.c = 3;
    return o.in.a*100 + o.in.b*10 + o.c;
}
