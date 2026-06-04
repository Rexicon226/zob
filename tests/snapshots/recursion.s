.text
.globl foo
.type foo, @function
foo:
    addi sp, sp, -32
    sd s2, 0(sp)
    sd s3, 8(sp)
    sd ra, 16(sp)
    mv s2, a0
    li t0, 0
    li t1, 0
    xor t2, s2, t1
    seqz t2, t2
    sltu t1, t0, t2
    li t2, 1
    beqz t1, .Lfoo_0
    mv s3, t2
    j .Lfoo_1
.Lfoo_0:
    subw t1, s2, t2
    mv a0, t1
    call foo
    mv t1, a0
    mv t2, t1
    mulw t1, s2, t2
    mv s3, t1
.Lfoo_1:
    mv a0, s3
    ld ra, 16(sp)
    ld s2, 0(sp)
    ld s3, 8(sp)
    addi sp, sp, 32
    ret
.size foo, .-foo
