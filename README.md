### Zig Optimizing Backend

## What is it?

I've dragged out my e-graph OIR (optimizable IR) into its own repo here for easier development. 
I've also commented it out like crazy in an attempt to make it more digestible.

This is hopefully to become the Zig compiler's optimizing layer/backend.
This research project's goals are to:
- Figure out what's best for the Zig project. What optimization method do we want?
- Document resources needed for implementing such a layer in the Zig compiler.
- Provide an implemented proof of concept in order to educate those who didn't spend
a god awful amount of time thinking this up and implementing it.

Implementation goals are:
- Implement an abstract optimizing IR based off of e-graphs and rvsdg.
- Implement a RISC-V machine code backend for proving a simpler method 
of register allocation and backend generalization.