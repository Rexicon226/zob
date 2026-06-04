.text
.globl foo
.type foo, @function
foo:
    mv t0, a0
    li t1, 100000
    addw t2, t0, t1
    mv t1, t2
    mul t2, t1, t1
    li t1, 10000000000
    xor t0, t2, t1
    seqz t0, t0
    mv a0, t0
    ret
.size foo, .-foo
