#include <stdint.h>
extern uint64_t foo();

int buf[64];
char text[64];

#ifndef EXPECT
#define EXPECT 0
#endif

int main(void) {
    return (EXPECT) ? 0 : 1;
}
