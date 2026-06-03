// Struct containing an array, copied by value; independent after copy.
// CHECK: foo()==34
struct A { int n; int data[3]; };
int foo(void) {
    struct A a; a.n = 5; a.data[1] = 20;
    struct A b = a;
    b.n = 9;                 // does not affect a
    return a.n + b.n + b.data[1];   // 5 + 9 + 20
}
