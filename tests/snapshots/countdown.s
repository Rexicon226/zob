.text
.globl foo
.type foo, @function
foo:
    addi sp, sp, -48
    sd s2, 0(sp)
    sd s3, 8(sp)
    sd s4, 16(sp)
    sd s5, 24(sp)
    sd s6, 32(sp)
    sd s7, 40(sp)
    mv t0, a0
    li t1, 0
    mv t2, t0
    mv t0, t1
.Lfoo_0:
    li t3, 0
    slt s2, t3, t2
    sltu s3, t1, s2
    xor s4, t0, t1
    seqz s4, s4
    and s5, s3, s4
    beqz s5, .Lfoo_1
    li s6, 1
    subw s7, t2, s6
    mv t2, s7
    mv t0, t1
    j .Lfoo_0
.Lfoo_1:
    mv t0, t2
    mv a0, t0
    ld s2, 0(sp)
    ld s3, 8(sp)
    ld s4, 16(sp)
    ld s5, 24(sp)
    ld s6, 32(sp)
    ld s7, 40(sp)
    addi sp, sp, 48
    ret
.size foo, .-foo
