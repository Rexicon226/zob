// EXPECT: foo("hello") == 5 && foo("") == 0
#include <string.h>
int foo(char *s) {
    return strlen(s);
}
