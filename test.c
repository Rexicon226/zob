// `switch` with a shared (empty fall-through) label group and a default.
// CHECK: foo(1)==10 && foo(2)==20 && foo(3)==20 && foo(7)==99
int foo(int x) {
    int r = 0;
    switch (x) {
        case 1: r = 10; break;
        case 3: {
          r = 20;
          while (r > 0) {
               r--;
          }
        }
    }
    return r;
}