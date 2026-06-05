.text
.globl foo
.type foo, @function
foo:
    li t0, -32
    add sp, sp, t0
    sd s2, 0(sp)
    sd s3, 8(sp)
    sd ra, 16(sp)
    mv s2, a0
    li t1, 0
    li t2, 0
    xor t3, s2, t2
    seqz t3, t3
    sltu t2, t1, t3
    li t3, 1
    beqz t2, .Lfoo_0
    mv s3, t3
    j .Lfoo_1
.Lfoo_0:
    subw t2, s2, t3
    mv a0, t2
    call foo
    mv t2, a0
    mv t3, t2
    mulw t2, s2, t3
    mv s3, t2
.Lfoo_1:
    mv a0, s3
    ld ra, 16(sp)
    ld s2, 0(sp)
    ld s3, 8(sp)
    li t0, 32
    add sp, sp, t0
    ret
.size foo, .-foo
