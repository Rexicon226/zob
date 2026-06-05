.text
.globl foo
.type foo, @function
foo:
    li t0, -192
    add sp, sp, t0
    sd s2, 112(sp)
    sd s3, 120(sp)
    sd s4, 128(sp)
    sd s5, 136(sp)
    sd s6, 144(sp)
    sd s7, 152(sp)
    sd s8, 160(sp)
    sd s9, 168(sp)
    sd s10, 176(sp)
    sd s11, 184(sp)
    mv t1, a0
    li t2, 0
    li t3, 0
    mv s2, t1
    mv t1, t2
    mv s3, t2
    mv s4, t3
.Lfoo_0:
    slt s5, s3, s2
    sltu s6, t3, s5
    xor s7, s4, t3
    seqz s7, s7
    and s8, s6, s7
    beqz s8, .Lfoo_1
    li s9, 1
    mv s10, s2
    mv s11, t1
    mv t4, s3
    sd t4, 0(sp)
    mv t4, t2
    sd t4, 8(sp)
    mv t4, t3
    sd t4, 16(sp)
.Lfoo_2:
    ld t5, 8(sp)
    slt t4, t5, s10
    sd t4, 24(sp)
    ld t6, 24(sp)
    sltu t4, t3, t6
    sd t4, 32(sp)
    ld t5, 16(sp)
    xor t4, t5, t3
    sd t4, 40(sp)
    ld t5, 40(sp)
    seqz t4, t5
    sd t4, 40(sp)
    ld t5, 32(sp)
    ld t6, 40(sp)
    and t4, t5, t6
    sd t4, 48(sp)
    ld t5, 48(sp)
    beqz t5, .Lfoo_3
    addw t4, s11, s9
    sd t4, 56(sp)
    ld t5, 8(sp)
    addw t4, t5, s9
    sd t4, 64(sp)
    mv t4, s10
    sd t4, 72(sp)
    ld t5, 0(sp)
    mv t4, t5
    sd t4, 80(sp)
    ld t5, 72(sp)
    mv s10, t5
    ld t5, 56(sp)
    mv s11, t5
    ld t5, 80(sp)
    mv t4, t5
    sd t4, 0(sp)
    ld t5, 64(sp)
    mv t4, t5
    sd t4, 8(sp)
    mv t4, t3
    sd t4, 16(sp)
    j .Lfoo_2
.Lfoo_3:
    mv t4, s11
    sd t4, 88(sp)
    addw t4, s3, s9
    sd t4, 96(sp)
    mv t4, s2
    sd t4, 104(sp)
    ld t5, 104(sp)
    mv s2, t5
    ld t5, 88(sp)
    mv t1, t5
    ld t5, 96(sp)
    mv s3, t5
    mv s4, t3
    j .Lfoo_0
.Lfoo_1:
    mv t3, t1
    mv a0, t3
    ld s2, 112(sp)
    ld s3, 120(sp)
    ld s4, 128(sp)
    ld s5, 136(sp)
    ld s6, 144(sp)
    ld s7, 152(sp)
    ld s8, 160(sp)
    ld s9, 168(sp)
    ld s10, 176(sp)
    ld s11, 184(sp)
    li t0, 192
    add sp, sp, t0
    ret
.size foo, .-foo
