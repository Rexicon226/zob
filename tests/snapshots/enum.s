.text
.globl foo
.type foo, @function
foo:
    li t0, -16
    add sp, sp, t0
    sd s2, 0(sp)
    sd s3, 8(sp)
    mv t1, a0
    li t2, 0
    li t3, 2
    xor s2, t1, t3
    seqz s2, s2
    sltu t3, t2, s2
    beqz t3, .Lfoo_0
    li t3, 6
    mv s2, t3
    j .Lfoo_1
.Lfoo_0:
    li t3, 0
    xor s3, t1, t3
    seqz s3, s3
    sltu t1, t2, s3
    beqz t1, .Lfoo_2
    mv t2, t3
    j .Lfoo_3
.Lfoo_2:
    li t3, 5
    mv t2, t3
.Lfoo_3:
    mv s2, t2
.Lfoo_1:
    mv a0, s2
    ld s2, 0(sp)
    ld s3, 8(sp)
    li t0, 16
    add sp, sp, t0
    ret
.size foo, .-foo
