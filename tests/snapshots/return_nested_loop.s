.text
.globl foo
.type foo, @function
foo:
    addi sp, sp, -288
    sd s2, 200(sp)
    sd s3, 208(sp)
    sd s4, 216(sp)
    sd s5, 224(sp)
    sd s6, 232(sp)
    sd s7, 240(sp)
    sd s8, 248(sp)
    sd s9, 256(sp)
    sd s10, 264(sp)
    sd s11, 272(sp)
    mv t0, a0
    li t1, 0
    li t2, 0
    mv t3, t0
    mv t0, t1
    mv s2, t2
    mv s3, t2
    mv s4, t2
.Lfoo_0:
    li s5, 10
    slt s6, t0, s5
    sltu s7, t2, s6
    xor s8, s2, t2
    seqz s8, s8
    and s9, s7, s8
    xor s10, s3, t2
    seqz s10, s10
    and s11, s9, s10
    beqz s11, .Lfoo_1
    li t4, 1
    sd t4, 0(sp)
    ld t6, 0(sp)
    addw t4, t0, t6
    sd t4, 8(sp)
    mv t4, t3
    sd t4, 16(sp)
    mv t4, t0
    sd t4, 24(sp)
    mv t4, t1
    sd t4, 32(sp)
    mv t4, t2
    sd t4, 40(sp)
    mv t4, t2
    sd t4, 48(sp)
    mv t4, t2
    sd t4, 56(sp)
.Lfoo_2:
    ld t5, 32(sp)
    slt t4, t5, s5
    sd t4, 64(sp)
    ld t6, 64(sp)
    sltu t4, t2, t6
    sd t4, 72(sp)
    ld t5, 40(sp)
    xor t4, t5, t2
    sd t4, 80(sp)
    ld t5, 80(sp)
    seqz t4, t5
    sd t4, 80(sp)
    ld t5, 72(sp)
    ld t6, 80(sp)
    and t4, t5, t6
    sd t4, 88(sp)
    ld t5, 48(sp)
    xor t4, t5, t2
    sd t4, 96(sp)
    ld t5, 96(sp)
    seqz t4, t5
    sd t4, 96(sp)
    ld t5, 88(sp)
    ld t6, 96(sp)
    and t4, t5, t6
    sd t4, 104(sp)
    ld t5, 104(sp)
    beqz t5, .Lfoo_3
    ld t5, 32(sp)
    ld t6, 0(sp)
    addw t4, t5, t6
    sd t4, 112(sp)
    ld t5, 24(sp)
    ld t6, 32(sp)
    mulw t4, t5, t6
    sd t4, 120(sp)
    ld t5, 16(sp)
    ld t6, 120(sp)
    xor t4, t5, t6
    sd t4, 128(sp)
    ld t5, 128(sp)
    seqz t4, t5
    sd t4, 128(sp)
    ld t6, 128(sp)
    sltu t4, t2, t6
    sd t4, 136(sp)
    ld t5, 24(sp)
    mulw t4, t5, s5
    sd t4, 144(sp)
    ld t5, 32(sp)
    ld t6, 144(sp)
    addw t4, t5, t6
    sd t4, 152(sp)
    ld t5, 16(sp)
    mv t4, t5
    sd t4, 160(sp)
    ld t5, 24(sp)
    mv t4, t5
    sd t4, 168(sp)
    ld t5, 160(sp)
    mv t4, t5
    sd t4, 16(sp)
    ld t5, 168(sp)
    mv t4, t5
    sd t4, 24(sp)
    ld t5, 112(sp)
    mv t4, t5
    sd t4, 32(sp)
    mv t4, t2
    sd t4, 40(sp)
    ld t5, 136(sp)
    mv t4, t5
    sd t4, 48(sp)
    ld t5, 152(sp)
    mv t4, t5
    sd t4, 56(sp)
    j .Lfoo_2
.Lfoo_3:
    ld t5, 48(sp)
    mv t4, t5
    sd t4, 176(sp)
    ld t5, 56(sp)
    mv t4, t5
    sd t4, 184(sp)
    mv t4, t3
    sd t4, 192(sp)
    ld t5, 192(sp)
    mv t3, t5
    ld t5, 8(sp)
    mv t0, t5
    mv s2, t2
    ld t5, 176(sp)
    mv s3, t5
    ld t5, 184(sp)
    mv s4, t5
    j .Lfoo_0
.Lfoo_1:
    mv t0, s3
    beqz t0, .Lfoo_4
    mv t0, s4
    mv s4, t0
    j .Lfoo_5
.Lfoo_4:
    li t0, -1
    mv s4, t0
.Lfoo_5:
    mv a0, s4
    ld s2, 200(sp)
    ld s3, 208(sp)
    ld s4, 216(sp)
    ld s5, 224(sp)
    ld s6, 232(sp)
    ld s7, 240(sp)
    ld s8, 248(sp)
    ld s9, 256(sp)
    ld s10, 264(sp)
    ld s11, 272(sp)
    addi sp, sp, 288
    ret
.size foo, .-foo
