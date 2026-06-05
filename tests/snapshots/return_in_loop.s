.text
.globl foo
.type foo, @function
foo:
    li t0, -144
    add sp, sp, t0
    sd s2, 64(sp)
    sd s3, 72(sp)
    sd s4, 80(sp)
    sd s5, 88(sp)
    sd s6, 96(sp)
    sd s7, 104(sp)
    sd s8, 112(sp)
    sd s9, 120(sp)
    sd s10, 128(sp)
    sd s11, 136(sp)
    mv t1, a0
    li t2, 0
    li t3, 0
    mv s2, t1
    mv t1, t2
    mv t2, t3
    mv s3, t3
    mv s4, t3
.Lfoo_0:
    li s5, 100
    slt s6, t1, s5
    sltu s7, t3, s6
    xor s8, t2, t3
    seqz s8, s8
    and s9, s7, s8
    xor s10, s3, t3
    seqz s10, s10
    and s11, s9, s10
    beqz s11, .Lfoo_1
    li t4, 1
    sd t4, 0(sp)
    ld t6, 0(sp)
    addw t4, t1, t6
    sd t4, 8(sp)
    mulw t4, t1, t1
    sd t4, 16(sp)
    ld t5, 16(sp)
    slt t4, t5, s2
    sd t4, 24(sp)
    ld t5, 24(sp)
    xor t4, t5, t3
    sd t4, 32(sp)
    ld t5, 32(sp)
    seqz t4, t5
    sd t4, 32(sp)
    ld t6, 32(sp)
    sltu t4, t3, t6
    sd t4, 40(sp)
    mv t4, s2
    sd t4, 48(sp)
    mv t4, t1
    sd t4, 56(sp)
    ld t5, 48(sp)
    mv s2, t5
    ld t5, 8(sp)
    mv t1, t5
    mv t2, t3
    ld t5, 40(sp)
    mv s3, t5
    ld t5, 56(sp)
    mv s4, t5
    j .Lfoo_0
.Lfoo_1:
    mv t2, s3
    beqz t2, .Lfoo_2
    mv t2, s4
    mv s4, t2
    j .Lfoo_3
.Lfoo_2:
    li t2, -1
    mv s4, t2
.Lfoo_3:
    mv a0, s4
    ld s2, 64(sp)
    ld s3, 72(sp)
    ld s4, 80(sp)
    ld s5, 88(sp)
    ld s6, 96(sp)
    ld s7, 104(sp)
    ld s8, 112(sp)
    ld s9, 120(sp)
    ld s10, 128(sp)
    ld s11, 136(sp)
    li t0, 144
    add sp, sp, t0
    ret
.size foo, .-foo
