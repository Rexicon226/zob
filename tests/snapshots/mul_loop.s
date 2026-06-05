.text
.globl foo
.type foo, @function
foo:
    li t0, -96
    add sp, sp, t0
    sd s2, 16(sp)
    sd s3, 24(sp)
    sd s4, 32(sp)
    sd s5, 40(sp)
    sd s6, 48(sp)
    sd s7, 56(sp)
    sd s8, 64(sp)
    sd s9, 72(sp)
    sd s10, 80(sp)
    sd s11, 88(sp)
    mv t1, a0
    mv t2, a1
    li t3, 0
    li s2, 0
    mv s3, t1
    mv t1, t3
    mv s4, t3
    mv t3, t2
    mv t2, s2
.Lfoo_0:
    slt s5, s4, t3
    sltu s6, s2, s5
    xor s7, t2, s2
    seqz s7, s7
    and s8, s6, s7
    beqz s8, .Lfoo_1
    addw s9, s3, t1
    li s10, 1
    addw s11, s4, s10
    mv t4, s3
    sd t4, 0(sp)
    mv t4, t3
    sd t4, 8(sp)
    ld t5, 0(sp)
    mv s3, t5
    mv t1, s9
    mv s4, s11
    ld t5, 8(sp)
    mv t3, t5
    mv t2, s2
    j .Lfoo_0
.Lfoo_1:
    mv s4, t1
    mv a0, s4
    ld s2, 16(sp)
    ld s3, 24(sp)
    ld s4, 32(sp)
    ld s5, 40(sp)
    ld s6, 48(sp)
    ld s7, 56(sp)
    ld s8, 64(sp)
    ld s9, 72(sp)
    ld s10, 80(sp)
    ld s11, 88(sp)
    li t0, 96
    add sp, sp, t0
    ret
.size foo, .-foo
