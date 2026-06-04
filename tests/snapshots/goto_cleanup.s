.text
.globl foo
.type foo, @function
foo:
    mv t0, a0
    li t1, 0
    li t2, 0
    slt t3, t0, t2
    sltu t2, t1, t3
    xor t3, t2, t1
    seqz t3, t3
    beqz t3, .Lfoo_0
    li t2, 10
    mulw t3, t0, t2
    mv t2, t3
    j .Lfoo_1
.Lfoo_0:
    li t3, -1
    mv t2, t3
.Lfoo_1:
    mv a0, t2
    ret
.size foo, .-foo
