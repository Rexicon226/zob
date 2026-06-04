.text
.globl foo
.type foo, @function
foo:
    addi sp, sp, -16
    sd s2, 0(sp)
    mv t0, a0
    li t1, 0
    li t2, 2
    xor t3, t0, t2
    seqz t3, t3
    sltu t2, t1, t3
    beqz t2, .Lfoo_0
    li t2, 6
    mv t3, t2
    j .Lfoo_1
.Lfoo_0:
    li t2, 0
    xor s2, t0, t2
    seqz s2, s2
    sltu t0, t1, s2
    beqz t0, .Lfoo_2
    mv t1, t2
    j .Lfoo_3
.Lfoo_2:
    li t2, 5
    mv t1, t2
.Lfoo_3:
    mv t3, t1
.Lfoo_1:
    mv a0, t3
    ld s2, 0(sp)
    addi sp, sp, 16
    ret
.size foo, .-foo
