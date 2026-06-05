.text
.globl foo
.type foo, @function
foo:
    li t0, -256
    add sp, sp, t0
    sd s2, 152(sp)
    sd s3, 160(sp)
    sd s4, 168(sp)
    sd s5, 176(sp)
    sd s6, 184(sp)
    sd s7, 192(sp)
    sd s8, 200(sp)
    sd s9, 208(sp)
    sd s10, 216(sp)
    sd s11, 224(sp)
    li t1, 0
    li t0, 232
    add t2, sp, t0
    li t3, 0
    li s2, 3
    li s3, 3
    li s4, 4
    li s5, 1
    mv s6, t1
    mv s7, t2
    mv s8, t3
.Lfoo_0:
    slt s9, s6, s2
    sltu s10, t3, s9
    xor s11, s8, t3
    seqz s11, s11
    and t4, s10, s11
    sd t4, 0(sp)
    ld t5, 0(sp)
    beqz t5, .Lfoo_1
    mv t4, s6
    sd t4, 8(sp)
    ld t5, 8(sp)
    sll t4, t5, s3
    sd t4, 16(sp)
    ld t6, 16(sp)
    add t4, s7, t6
    sd t4, 24(sp)
    ld t6, 24(sp)
    sw s6, 0(t6)
    ld t5, 24(sp)
    add t4, t5, s4
    sd t4, 32(sp)
    li t4, 100
    sd t4, 40(sp)
    ld t6, 40(sp)
    mulw t4, s6, t6
    sd t4, 48(sp)
    ld t5, 48(sp)
    ld t6, 32(sp)
    sw t5, 0(t6)
    addw t4, s6, s5
    sd t4, 56(sp)
    mv t4, s7
    sd t4, 64(sp)
    ld t5, 56(sp)
    mv s6, t5
    ld t5, 64(sp)
    mv s7, t5
    mv s8, t3
    j .Lfoo_0
.Lfoo_1:
    mv s7, t1
    mv s8, t1
    mv t1, t2
    mv t2, t3
.Lfoo_2:
    slt s9, s8, s2
    sltu s10, t3, s9
    xor s11, t2, t3
    seqz s11, s11
    and s6, s10, s11
    beqz s6, .Lfoo_3
    mv t4, s8
    sd t4, 72(sp)
    ld t5, 72(sp)
    sll t4, t5, s3
    sd t4, 80(sp)
    ld t6, 80(sp)
    add t4, t1, t6
    sd t4, 88(sp)
    ld t5, 88(sp)
    lw t4, 0(t5)
    sd t4, 96(sp)
    ld t6, 96(sp)
    addw t4, s7, t6
    sd t4, 104(sp)
    ld t5, 88(sp)
    add t4, t5, s4
    sd t4, 112(sp)
    ld t5, 112(sp)
    lw t4, 0(t5)
    sd t4, 120(sp)
    ld t5, 104(sp)
    ld t6, 120(sp)
    addw t4, t5, t6
    sd t4, 128(sp)
    addw t4, s8, s5
    sd t4, 136(sp)
    mv t4, t1
    sd t4, 144(sp)
    ld t5, 128(sp)
    mv s7, t5
    ld t5, 136(sp)
    mv s8, t5
    ld t5, 144(sp)
    mv t1, t5
    mv t2, t3
    j .Lfoo_2
.Lfoo_3:
    mv t3, s7
    mv a0, t3
    ld s2, 152(sp)
    ld s3, 160(sp)
    ld s4, 168(sp)
    ld s5, 176(sp)
    ld s6, 184(sp)
    ld s7, 192(sp)
    ld s8, 200(sp)
    ld s9, 208(sp)
    ld s10, 216(sp)
    ld s11, 224(sp)
    li t0, 256
    add sp, sp, t0
    ret
.size foo, .-foo
