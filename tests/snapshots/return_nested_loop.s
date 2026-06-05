.text
.globl foo
.type foo, @function
foo:
    li t0, -288
    add sp, sp, t0
    sd s2, 208(sp)
    sd s3, 216(sp)
    sd s4, 224(sp)
    sd s5, 232(sp)
    sd s6, 240(sp)
    sd s7, 248(sp)
    sd s8, 256(sp)
    sd s9, 264(sp)
    sd s10, 272(sp)
    sd s11, 280(sp)
    mv t1, a0
    li t2, 0
    li t3, 0
    mv s2, t1
    mv t1, t2
    mv s3, t3
    mv s4, t3
    mv s5, t3
.Lfoo_0:
    li s6, 10
    slt s7, t1, s6
    sltu s8, t3, s7
    xor s9, s3, t3
    seqz s9, s9
    and s10, s8, s9
    xor s11, s4, t3
    seqz s11, s11
    and t4, s10, s11
    sd t4, 0(sp)
    ld t5, 0(sp)
    beqz t5, .Lfoo_1
    li t4, 1
    sd t4, 8(sp)
    ld t6, 8(sp)
    addw t4, t1, t6
    sd t4, 16(sp)
    mv t4, s2
    sd t4, 24(sp)
    mv t4, t1
    sd t4, 32(sp)
    mv t4, t2
    sd t4, 40(sp)
    mv t4, t3
    sd t4, 48(sp)
    mv t4, t3
    sd t4, 56(sp)
    mv t4, t3
    sd t4, 64(sp)
.Lfoo_2:
    ld t5, 40(sp)
    slt t4, t5, s6
    sd t4, 72(sp)
    ld t6, 72(sp)
    sltu t4, t3, t6
    sd t4, 80(sp)
    ld t5, 48(sp)
    xor t4, t5, t3
    sd t4, 88(sp)
    ld t5, 88(sp)
    seqz t4, t5
    sd t4, 88(sp)
    ld t5, 80(sp)
    ld t6, 88(sp)
    and t4, t5, t6
    sd t4, 96(sp)
    ld t5, 56(sp)
    xor t4, t5, t3
    sd t4, 104(sp)
    ld t5, 104(sp)
    seqz t4, t5
    sd t4, 104(sp)
    ld t5, 96(sp)
    ld t6, 104(sp)
    and t4, t5, t6
    sd t4, 112(sp)
    ld t5, 112(sp)
    beqz t5, .Lfoo_3
    ld t5, 40(sp)
    ld t6, 8(sp)
    addw t4, t5, t6
    sd t4, 120(sp)
    ld t5, 32(sp)
    ld t6, 40(sp)
    mulw t4, t5, t6
    sd t4, 128(sp)
    ld t5, 24(sp)
    ld t6, 128(sp)
    xor t4, t5, t6
    sd t4, 136(sp)
    ld t5, 136(sp)
    seqz t4, t5
    sd t4, 136(sp)
    ld t6, 136(sp)
    sltu t4, t3, t6
    sd t4, 144(sp)
    ld t5, 32(sp)
    mulw t4, t5, s6
    sd t4, 152(sp)
    ld t5, 40(sp)
    ld t6, 152(sp)
    addw t4, t5, t6
    sd t4, 160(sp)
    ld t5, 24(sp)
    mv t4, t5
    sd t4, 168(sp)
    ld t5, 32(sp)
    mv t4, t5
    sd t4, 176(sp)
    ld t5, 168(sp)
    mv t4, t5
    sd t4, 24(sp)
    ld t5, 176(sp)
    mv t4, t5
    sd t4, 32(sp)
    ld t5, 120(sp)
    mv t4, t5
    sd t4, 40(sp)
    mv t4, t3
    sd t4, 48(sp)
    ld t5, 144(sp)
    mv t4, t5
    sd t4, 56(sp)
    ld t5, 160(sp)
    mv t4, t5
    sd t4, 64(sp)
    j .Lfoo_2
.Lfoo_3:
    ld t5, 56(sp)
    mv t4, t5
    sd t4, 184(sp)
    ld t5, 64(sp)
    mv t4, t5
    sd t4, 192(sp)
    mv t4, s2
    sd t4, 200(sp)
    ld t5, 200(sp)
    mv s2, t5
    ld t5, 16(sp)
    mv t1, t5
    mv s3, t3
    ld t5, 184(sp)
    mv s4, t5
    ld t5, 192(sp)
    mv s5, t5
    j .Lfoo_0
.Lfoo_1:
    mv t1, s4
    beqz t1, .Lfoo_4
    mv t1, s5
    mv s5, t1
    j .Lfoo_5
.Lfoo_4:
    li t1, -1
    mv s5, t1
.Lfoo_5:
    mv a0, s5
    ld s2, 208(sp)
    ld s3, 216(sp)
    ld s4, 224(sp)
    ld s5, 232(sp)
    ld s6, 240(sp)
    ld s7, 248(sp)
    ld s8, 256(sp)
    ld s9, 264(sp)
    ld s10, 272(sp)
    ld s11, 280(sp)
    li t0, 288
    add sp, sp, t0
    ret
.size foo, .-foo
