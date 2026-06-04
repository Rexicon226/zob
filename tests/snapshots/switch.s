.text
.globl foo
.type foo, @function
foo:
    addi sp, sp, -16
    sd s2, 0(sp)
    mv t0, a0
    li t1, 1
    xor t2, t0, t1
    seqz t2, t2
    beqz t2, .Lfoo_0
    li t2, 10
    mv t1, t2
    j .Lfoo_1
.Lfoo_0:
    li t2, 2
    xor t3, t0, t2
    seqz t3, t3
    li t2, 3
    xor s2, t0, t2
    seqz s2, s2
    add t2, t3, s2
    beqz t2, .Lfoo_2
    li t3, 20
    mv t2, t3
    j .Lfoo_3
.Lfoo_2:
    li t3, 99
    mv t2, t3
.Lfoo_3:
    mv t1, t2
.Lfoo_1:
    mv a0, t1
    ld s2, 0(sp)
    addi sp, sp, 16
    ret
.size foo, .-foo
