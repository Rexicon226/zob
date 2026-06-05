.text
.globl foo
.type foo, @function
foo:
    mv t1, a0
    li t2, 100000
    addw t3, t1, t2
    mv t2, t3
    mul t3, t2, t2
    li t2, 10000000000
    xor t1, t3, t2
    seqz t1, t1
    mv a0, t1
    ret
.size foo, .-foo
