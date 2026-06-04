// A bit of K&R tom-foolery, so that any declaration we insert will work here.
#include <stdint.h>
extern uint64_t foo();

int buf[64];
char text[64];

#ifndef CHECK
#define CHECK 0
#endif

int main(void) {
    return (CHECK) ? 0 : 1;
}
