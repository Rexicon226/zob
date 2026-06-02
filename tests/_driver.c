// A bit of K&R tom-foolery, so that any declaration we insert will work here.
extern int foo();

int buf[64];

#ifndef CHECK
#define CHECK 0
#endif

int main(void) {
    return (CHECK) ? 0 : 1;
}
