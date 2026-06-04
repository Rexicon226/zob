// EXPECT: foo()==14
struct P { int x; int y; };
int gety(struct P *p) { return p->y; }
void setx(struct P *p, int v) { p->x = v; }
int foo(void) {
    struct P p;
    p.x = 1; p.y = 9;
    setx(&p, 5);
    return gety(&p) + p.x;
}
