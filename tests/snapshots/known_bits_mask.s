.text
.globl foo
.type foo, @function
foo:
    mv t0, a0
    slli t1, t0, 56
    srai t1, t1, 56
    andi t0, t1, 255
    mv a0, t0
    ret
.size foo, .-foo
