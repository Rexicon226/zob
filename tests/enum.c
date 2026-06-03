// CHECK: foo(0)==0 && foo(1)==5 && foo(2)==6
enum Color { RED, GREEN = 5, BLUE };
int foo(int x) {
    enum Color c = GREEN;
    if (x == 0) c = RED;
    if (x == 2) c = BLUE;
    return c;
}
