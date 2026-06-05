.text
.globl foo
.type foo, @function
foo:
    li t0, -64
    add sp, sp, t0
    sd s2, 0(sp)
    sd s3, 8(sp)
    sd s4, 16(sp)
    sd s5, 24(sp)
    sd s6, 32(sp)
    sd s7, 40(sp)
    sd s8, 48(sp)
    mv t1, a0
    li t2, 0
    mv t3, t1
    mv t1, t2
.Lfoo_0:
    li s2, 0
    slt s3, s2, t3
    sltu s4, t2, s3
    xor s5, t1, t2
    seqz s5, s5
    and s6, s4, s5
    beqz s6, .Lfoo_1
    li s7, 1
    subw s8, t3, s7
    mv t3, s8
    mv t1, t2
    j .Lfoo_0
.Lfoo_1:
    mv t1, t3
    mv a0, t1
    ld s2, 0(sp)
    ld s3, 8(sp)
    ld s4, 16(sp)
    ld s5, 24(sp)
    ld s6, 32(sp)
    ld s7, 40(sp)
    ld s8, 48(sp)
    li t0, 64
    add sp, sp, t0
    ret
.size foo, .-foo
