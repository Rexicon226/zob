.text
.globl foo
.type foo, @function
foo:
    mv t0, a0
    li t1, 60
    and t2, t0, t1
    li t1, 128
    or t0, t2, t1
    li t1, 168
    xor t2, t0, t1
    li t1, 2
    sllw t0, t2, t1
    li t1, 1
    sraw t2, t0, t1
    mv a0, t2
    ret
.size foo, .-foo
