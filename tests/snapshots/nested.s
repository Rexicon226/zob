.text
.globl foo
.type foo, @function
foo:
    addi sp, sp, -192
    sd s2, 104(sp)
    sd s3, 112(sp)
    sd s4, 120(sp)
    sd s5, 128(sp)
    sd s6, 136(sp)
    sd s7, 144(sp)
    sd s8, 152(sp)
    sd s9, 160(sp)
    sd s10, 168(sp)
    sd s11, 176(sp)
    mv t0, a0
    li t1, 0
    li t2, 0
    mv t3, t0
    mv t0, t1
    mv s2, t1
    mv s3, t2
.Lfoo_0:
    slt s4, s2, t3
    sltu s5, t2, s4
    xor s6, s3, t2
    seqz s6, s6
    and s7, s5, s6
    beqz s7, .Lfoo_1
    li s8, 1
    mv s9, t3
    mv s10, t0
    mv s11, s2
    mv t4, t1
    sd t4, 0(sp)
    mv t4, t2
    sd t4, 8(sp)
.Lfoo_2:
    ld t5, 0(sp)
    slt t4, t5, s9
    sd t4, 16(sp)
    ld t6, 16(sp)
    sltu t4, t2, t6
    sd t4, 24(sp)
    ld t5, 8(sp)
    xor t4, t5, t2
    sd t4, 32(sp)
    ld t5, 32(sp)
    seqz t4, t5
    sd t4, 32(sp)
    ld t5, 24(sp)
    ld t6, 32(sp)
    and t4, t5, t6
    sd t4, 40(sp)
    ld t5, 40(sp)
    beqz t5, .Lfoo_3
    addw t4, s10, s8
    sd t4, 48(sp)
    ld t5, 0(sp)
    addw t4, t5, s8
    sd t4, 56(sp)
    mv t4, s9
    sd t4, 64(sp)
    mv t4, s11
    sd t4, 72(sp)
    ld t5, 64(sp)
    mv s9, t5
    ld t5, 48(sp)
    mv s10, t5
    ld t5, 72(sp)
    mv s11, t5
    ld t5, 56(sp)
    mv t4, t5
    sd t4, 0(sp)
    mv t4, t2
    sd t4, 8(sp)
    j .Lfoo_2
.Lfoo_3:
    mv t4, s10
    sd t4, 80(sp)
    addw t4, s2, s8
    sd t4, 88(sp)
    mv t4, t3
    sd t4, 96(sp)
    ld t5, 96(sp)
    mv t3, t5
    ld t5, 80(sp)
    mv t0, t5
    ld t5, 88(sp)
    mv s2, t5
    mv s3, t2
    j .Lfoo_0
.Lfoo_1:
    mv t2, t0
    mv a0, t2
    ld s2, 104(sp)
    ld s3, 112(sp)
    ld s4, 120(sp)
    ld s5, 128(sp)
    ld s6, 136(sp)
    ld s7, 144(sp)
    ld s8, 152(sp)
    ld s9, 160(sp)
    ld s10, 168(sp)
    ld s11, 176(sp)
    addi sp, sp, 192
    ret
.size foo, .-foo
