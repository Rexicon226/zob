.text
.globl foo
.type foo, @function
foo:
    mv t0, a0
    li t1, 1
    xor t2, t0, t1
    seqz t2, t2
    beqz t2, .Lfoo_0
    li t2, 5
    mv t1, t2
    j .Lfoo_1
.Lfoo_0:
    li t2, 2
    xor t3, t0, t2
    seqz t3, t3
    beqz t3, .Lfoo_2
    li t2, 6
    mv t3, t2
    j .Lfoo_3
.Lfoo_2:
    li t2, -1
    mv t3, t2
.Lfoo_3:
    mv t1, t3
.Lfoo_1:
    mv a0, t1
    ret
.size foo, .-foo
