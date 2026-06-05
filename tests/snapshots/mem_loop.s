.text
.globl foo
.type foo, @function
foo:
    li t0, -96
    add sp, sp, t0
    sd s2, 8(sp)
    sd s3, 16(sp)
    sd s4, 24(sp)
    sd s5, 32(sp)
    sd s6, 40(sp)
    sd s7, 48(sp)
    sd s8, 56(sp)
    sd s9, 64(sp)
    sd s10, 72(sp)
    sd s11, 80(sp)
    mv t1, a1
    mv t2, a0
    li t3, 0
    li s2, 0
    mv s3, t1
    mv t1, t3
    mv t3, t2
    mv s4, s2
.Lfoo_0:
    slt s5, t1, s3
    sltu s6, s2, s5
    xor s7, s4, s2
    seqz s7, s7
    and s8, s6, s7
    beqz s8, .Lfoo_1
    sw t1, 0(t3)
    li s9, 1
    addw s10, t1, s9
    mv s11, s3
    mv t4, t3
    sd t4, 0(sp)
    mv s3, s11
    mv t1, s10
    ld t5, 0(sp)
    mv t3, t5
    mv s4, s2
    j .Lfoo_0
.Lfoo_1:
    lw t1, 0(t2)
    mv a0, t1
    ld s2, 8(sp)
    ld s3, 16(sp)
    ld s4, 24(sp)
    ld s5, 32(sp)
    ld s6, 40(sp)
    ld s7, 48(sp)
    ld s8, 56(sp)
    ld s9, 64(sp)
    ld s10, 72(sp)
    ld s11, 80(sp)
    li t0, 96
    add sp, sp, t0
    ret
.size foo, .-foo
