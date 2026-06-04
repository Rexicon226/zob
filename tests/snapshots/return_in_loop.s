.text
.globl foo
.type foo, @function
foo:
    addi sp, sp, -144
    sd s2, 56(sp)
    sd s3, 64(sp)
    sd s4, 72(sp)
    sd s5, 80(sp)
    sd s6, 88(sp)
    sd s7, 96(sp)
    sd s8, 104(sp)
    sd s9, 112(sp)
    sd s10, 120(sp)
    sd s11, 128(sp)
    mv t0, a0
    li t1, 0
    li t2, 0
    mv t3, t0
    mv t0, t1
    mv t1, t2
    mv s2, t2
    mv s3, t2
.Lfoo_0:
    li s4, 100
    slt s5, t0, s4
    sltu s6, t2, s5
    xor s7, t1, t2
    seqz s7, s7
    and s8, s6, s7
    xor s9, s2, t2
    seqz s9, s9
    and s10, s8, s9
    beqz s10, .Lfoo_1
    li s11, 1
    addw t4, t0, s11
    sd t4, 0(sp)
    mulw t4, t0, t0
    sd t4, 8(sp)
    ld t5, 8(sp)
    slt t4, t5, t3
    sd t4, 16(sp)
    ld t5, 16(sp)
    xor t4, t5, t2
    sd t4, 24(sp)
    ld t5, 24(sp)
    seqz t4, t5
    sd t4, 24(sp)
    ld t6, 24(sp)
    sltu t4, t2, t6
    sd t4, 32(sp)
    mv t4, t3
    sd t4, 40(sp)
    mv t4, t0
    sd t4, 48(sp)
    ld t5, 40(sp)
    mv t3, t5
    ld t5, 0(sp)
    mv t0, t5
    mv t1, t2
    ld t5, 32(sp)
    mv s2, t5
    ld t5, 48(sp)
    mv s3, t5
    j .Lfoo_0
.Lfoo_1:
    mv t1, s2
    beqz t1, .Lfoo_2
    mv t1, s3
    mv s3, t1
    j .Lfoo_3
.Lfoo_2:
    li t1, -1
    mv s3, t1
.Lfoo_3:
    mv a0, s3
    ld s2, 56(sp)
    ld s3, 64(sp)
    ld s4, 72(sp)
    ld s5, 80(sp)
    ld s6, 88(sp)
    ld s7, 96(sp)
    ld s8, 104(sp)
    ld s9, 112(sp)
    ld s10, 120(sp)
    ld s11, 128(sp)
    addi sp, sp, 144
    ret
.size foo, .-foo
