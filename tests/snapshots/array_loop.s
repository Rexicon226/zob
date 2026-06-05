.text
.globl foo
.type foo, @function
foo:
    li t0, -256
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
    li t0, 192
    add t2, sp, t0
    li t3, 0
    li s2, 0
    li s3, 2
    li s4, 1
    mv s5, t1
    mv s6, t2
    mv s7, t3
    mv s8, s2
.Lfoo_0:
    slt s9, s7, s5
    sltu s10, s2, s9
    xor s11, s8, s2
    seqz s11, s11
    and t4, s10, s11
    sd t4, 0(sp)
    ld t5, 0(sp)
    beqz t5, .Lfoo_1
    mv t4, s7
    sd t4, 8(sp)
    ld t5, 8(sp)
    sll t4, t5, s3
    sd t4, 16(sp)
    ld t6, 16(sp)
    add t4, s6, t6
    sd t4, 24(sp)
    ld t6, 24(sp)
    sw s7, 0(t6)
    addw t4, s7, s4
    sd t4, 32(sp)
    mv t4, s5
    sd t4, 40(sp)
    mv t4, s6
    sd t4, 48(sp)
    ld t5, 40(sp)
    mv s5, t5
    ld t5, 48(sp)
    mv s6, t5
    ld t5, 32(sp)
    mv s7, t5
    mv s8, s2
    j .Lfoo_0
.Lfoo_1:
    mv s6, t1
    mv t1, t2
    mv t2, t3
    mv s7, t3
    mv t3, s2
.Lfoo_2:
    slt s8, t2, s6
    sltu s9, s2, s8
    xor s10, t3, s2
    seqz s10, s10
    and s11, s9, s10
    beqz s11, .Lfoo_3
    addw s5, t2, s4
    mv t4, t2
    sd t4, 56(sp)
    ld t5, 56(sp)
    sll t4, t5, s3
    sd t4, 64(sp)
    ld t6, 64(sp)
    add t4, t1, t6
    sd t4, 72(sp)
    ld t5, 72(sp)
    lw t4, 0(t5)
    sd t4, 80(sp)
    ld t6, 80(sp)
    addw t4, s7, t6
    sd t4, 88(sp)
    mv t4, s6
    sd t4, 96(sp)
    mv t4, t1
    sd t4, 104(sp)
    ld t5, 96(sp)
    mv s6, t5
    ld t5, 104(sp)
    mv t1, t5
    mv t2, s5
    ld t5, 88(sp)
    mv s7, t5
    mv t3, s2
    j .Lfoo_2
.Lfoo_3:
    mv t1, s7
    mv a0, t1
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
    li t0, 256
    add sp, sp, t0
    ret
.size foo, .-foo
