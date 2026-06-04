// EXPECT: foo(0, 0xAABB)==0xBBAA && foo(1, 0xAABBCCDDU)==0xDDCCBBAAU && foo(2, 0x0011223344556677UL)==0x7766554433221100UL
#include <stdint.h>
#include <stdlib.h>
uint64_t foo(int c, uint64_t input) {
    switch (c) {
        case 0: return __bswap_16(input);
        case 1: return __bswap_32(input);
        case 2: return __bswap_64(input);
        default: return 0;
    }
}