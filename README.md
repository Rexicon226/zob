 ### Zig Optimizing Backend

This is sort of two projects in one. The first goal is to develop a prototype optimizing backend
for the Zig compiler, testing out different IRs and representations, to find the one that will
suite Zig the best. A second goal is to create a general optimizing backend, one that can be used
as for simple compiled languages, test out new and interesting optimizations, and just see how Zig
fairs as a language, for writing optimizers.

The current implementation is a mix of E-Graphs and RVSDG. This allows for some
truly unique and interesting optimization flows, which I don't believe have been
explored in depth, if at all, in modern optimization frameworks. For compatibility
with Zig's SSA, this will require developing some new re-looper algorithms for
construction the flow we need, but it should be doable. In the near future I'd 
like to mock up Zig's SSA in a simple sandbox here and write such an algorithm.

Implementation goals are:
- Implement an abstract optimizing IR based on e-graphs and rvsdg.
- Implement a RISC-V machine code backend to provide a simpler method 
of register allocation and backend generalization.
