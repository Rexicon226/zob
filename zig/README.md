###

`root.zig` acts as a shim into the Zig compiler repo. Since it doesn't expose
any of its internals at the moment, we need to download the compiler as a dependency
and create a module inside of it, which we expose as a library.

In order to "drive" these internals, there is a `driver.zig` file which interacts with 
this exposed Zig compiler module, and works to output AIR, which our optimizing backend
will then use.