.text
.globl foo
.type foo, @function
foo:
    mv t0, a0
    slli t1, t0, 48
    srai t1, t1, 48
    mv t0, t1
    mv a0, t0
    ret
.size foo, .-foo
