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
    mv s2, t1
    mv t1, t2
.Lfoo_0:
    slt s3, s2, t3
    sltu s4, t2, s3
    xor s5, t1, t2
    seqz s5, s5
    and s6, s4, s5
    beqz s6, .Lfoo_1
    li s7, 4
    xor s8, s2, s7
    seqz s8, s8
    beqz s8, .Lfoo_2
    mv s9, t0
    j .Lfoo_3
.Lfoo_2:
    li s10, 2
    xor s11, s2, s10
    seqz s11, s11
    beqz s11, .Lfoo_4
    li t4, 100
    sd t4, 0(sp)
    ld t6, 0(sp)
    addw t4, t0, t6
    sd t4, 8(sp)
    ld t5, 8(sp)
    mv t4, t5
    sd t4, 16(sp)
    j .Lfoo_5
.Lfoo_4:
    addw t4, t0, s2
    sd t4, 24(sp)
    ld t5, 24(sp)
    mv t4, t5
    sd t4, 16(sp)
.Lfoo_5:
    ld t5, 16(sp)
    mv s9, t5
.Lfoo_3:
    li t4, 1
    sd t4, 32(sp)
    ld t6, 32(sp)
    addw t4, s2, t6
    sd t4, 40(sp)
    mv t4, t3
    sd t4, 48(sp)
    ld t5, 48(sp)
    mv t3, t5
    mv t0, s9
    ld t5, 40(sp)
    mv s2, t5
    mv t1, t2
    j .Lfoo_0
.Lfoo_1:
    mv t2, t0
    mv a0, t2
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
