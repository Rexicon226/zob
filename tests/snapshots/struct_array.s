.text
.globl foo
.type foo, @function
foo:
    addi sp, sp, -240
    sd s2, 136(sp)
    sd s3, 144(sp)
    sd s4, 152(sp)
    sd s5, 160(sp)
    sd s6, 168(sp)
    sd s7, 176(sp)
    sd s8, 184(sp)
    sd s9, 192(sp)
    sd s10, 200(sp)
    sd s11, 208(sp)
    li t0, 0
    addi t1, sp, 216
    li t2, 0
    li t3, 3
    li s2, 3
    li s3, 4
    li s4, 1
    mv s5, t0
    mv s6, t1
    mv s7, t2
.Lfoo_0:
    slt s8, s5, t3
    sltu s9, t2, s8
    xor s10, s7, t2
    seqz s10, s10
    and s11, s9, s10
    beqz s11, .Lfoo_1
    mv t4, s5
    sd t4, 0(sp)
    ld t5, 0(sp)
    sll t4, t5, s2
    sd t4, 8(sp)
    ld t6, 8(sp)
    add t4, s6, t6
    sd t4, 16(sp)
    ld t6, 16(sp)
    sw s5, 0(t6)
    ld t5, 16(sp)
    add t4, t5, s3
    sd t4, 24(sp)
    li t4, 100
    sd t4, 32(sp)
    ld t6, 32(sp)
    mulw t4, s5, t6
    sd t4, 40(sp)
    ld t5, 40(sp)
    ld t6, 24(sp)
    sw t5, 0(t6)
    addw t4, s5, s4
    sd t4, 48(sp)
    mv t4, s6
    sd t4, 56(sp)
    ld t5, 48(sp)
    mv s5, t5
    ld t5, 56(sp)
    mv s6, t5
    mv s7, t2
    j .Lfoo_0
.Lfoo_1:
    mv s6, t0
    mv s7, t0
    mv t0, t1
    mv t1, t2
.Lfoo_2:
    slt s8, s7, t3
    sltu s9, t2, s8
    xor s10, t1, t2
    seqz s10, s10
    and s11, s9, s10
    beqz s11, .Lfoo_3
    mv s5, s7
    sll t4, s5, s2
    sd t4, 64(sp)
    ld t6, 64(sp)
    add t4, t0, t6
    sd t4, 72(sp)
    ld t5, 72(sp)
    lw t4, 0(t5)
    sd t4, 80(sp)
    ld t6, 80(sp)
    addw t4, s6, t6
    sd t4, 88(sp)
    ld t5, 72(sp)
    add t4, t5, s3
    sd t4, 96(sp)
    ld t5, 96(sp)
    lw t4, 0(t5)
    sd t4, 104(sp)
    ld t5, 88(sp)
    ld t6, 104(sp)
    addw t4, t5, t6
    sd t4, 112(sp)
    addw t4, s7, s4
    sd t4, 120(sp)
    mv t4, t0
    sd t4, 128(sp)
    ld t5, 112(sp)
    mv s6, t5
    ld t5, 120(sp)
    mv s7, t5
    ld t5, 128(sp)
    mv t0, t5
    mv t1, t2
    j .Lfoo_2
.Lfoo_3:
    mv t2, s6
    mv a0, t2
    ld s2, 136(sp)
    ld s3, 144(sp)
    ld s4, 152(sp)
    ld s5, 160(sp)
    ld s6, 168(sp)
    ld s7, 176(sp)
    ld s8, 184(sp)
    ld s9, 192(sp)
    ld s10, 200(sp)
    ld s11, 208(sp)
    addi sp, sp, 240
    ret
.size foo, .-foo
