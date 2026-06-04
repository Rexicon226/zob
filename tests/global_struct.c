// EXPECT: foo()==30
struct S { int x; char y; long z; };
struct S s[2] = { {.x = 10}, {.y = 20} };

int foo(void) {
    return s[0].x + s[0].y + s[1].x + s[1].y;
}