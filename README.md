 ### Zig Optimizing Backend

This is sort of two projects in one. The first goal is to develop a prototype optimizing backend
for the Zig compiler, testing out different IRs and representations, to find the one that will
suite Zig the best. A second goal is to create a general optimizing backend, one that can be used
as for simple compiled languages, test out new and interesting optimizations, and just see how Zig
fairs as a language, for writing optimizers.

The current implementation is a mix of E-Graphs and Sea of Nodes. At first, I was keen on using RVSDG
since given Zig's very structural nature it seemed like it would be a good fit, however after a few
months of fiddling around with it, RVSDG is just too restrictive. This is likely just my own experience,
but I found it extremely difficult to develop algorithms to convert from Zig's SSA to RVSDG.
Maybe I'll come back to it one day, but for now, I'd like to use something a bit less esoteric, such as 
SoN, and move further in the implementation.

Implementation goals are:
- Implement an abstract optimizing IR based on e-graphs, rvsdg, and SoN.
- Implement a RISC-V machine code backend to provide a simpler method 
of register allocation and backend generalization.
