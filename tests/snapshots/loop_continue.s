.text
.globl foo
.type foo, @function
foo:
    li t0, -112
    add sp, sp, t0
    sd s2, 32(sp)
    sd s3, 40(sp)
    sd s4, 48(sp)
    sd s5, 56(sp)
    sd s6, 64(sp)
    sd s7, 72(sp)
    sd s8, 80(sp)
    sd s9, 88(sp)
    sd s10, 96(sp)
    sd s11, 104(sp)
    mv t1, a0
    li t2, 0
    li t3, 0
    mv s2, t1
    mv t1, t2
    mv s3, t2
    mv t2, t3
.Lfoo_0:
    slt s4, s3, s2
    sltu s5, t3, s4
    xor s6, t2, t3
    seqz s6, s6
    and s7, s5, s6
    beqz s7, .Lfoo_1
    li s8, 2
    xor s9, s3, s8
    seqz s9, s9
    sltu s10, t3, s9
    beqz s10, .Lfoo_2
    mv s11, t1
    j .Lfoo_3
.Lfoo_2:
    addw t4, t1, s3
    sd t4, 0(sp)
    ld t5, 0(sp)
    mv s11, t5
.Lfoo_3:
    li t4, 1
    sd t4, 8(sp)
    ld t6, 8(sp)
    addw t4, s3, t6
    sd t4, 16(sp)
    mv t4, s2
    sd t4, 24(sp)
    ld t5, 24(sp)
    mv s2, t5
    mv t1, s11
    ld t5, 16(sp)
    mv s3, t5
    mv t2, t3
    j .Lfoo_0
.Lfoo_1:
    mv t3, t1
    mv a0, t3
    ld s2, 32(sp)
    ld s3, 40(sp)
    ld s4, 48(sp)
    ld s5, 56(sp)
    ld s6, 64(sp)
    ld s7, 72(sp)
    ld s8, 80(sp)
    ld s9, 88(sp)
    ld s10, 96(sp)
    ld s11, 104(sp)
    li t0, 112
    add sp, sp, t0
    ret
.size foo, .-foo
