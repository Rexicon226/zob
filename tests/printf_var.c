// EXPECT: foo(42) == 13
#include <stdio.h>
int foo(int x) {
    return printf("something %d\n", x);
}
