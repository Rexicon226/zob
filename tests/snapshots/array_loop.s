.text
.globl foo
.type foo, @function
foo:
    addi sp, sp, -240
    sd s2, 96(sp)
    sd s3, 104(sp)
    sd s4, 112(sp)
    sd s5, 120(sp)
    sd s6, 128(sp)
    sd s7, 136(sp)
    sd s8, 144(sp)
    sd s9, 152(sp)
    sd s10, 160(sp)
    sd s11, 168(sp)
    mv t0, a0
    addi t1, sp, 176
    li t2, 0
    li t3, 0
    li s2, 2
    li s3, 1
    mv s4, t0
    mv s5, t1
    mv s6, t2
    mv s7, t3
.Lfoo_0:
    slt s8, s6, s4
    sltu s9, t3, s8
    xor s10, s7, t3
    seqz s10, s10
    and s11, s9, s10
    beqz s11, .Lfoo_1
    mv t4, s6
    sd t4, 0(sp)
    ld t5, 0(sp)
    sll t4, t5, s2
    sd t4, 8(sp)
    ld t6, 8(sp)
    add t4, s5, t6
    sd t4, 16(sp)
    ld t6, 16(sp)
    sw s6, 0(t6)
    addw t4, s6, s3
    sd t4, 24(sp)
    mv t4, s4
    sd t4, 32(sp)
    mv t4, s5
    sd t4, 40(sp)
    ld t5, 32(sp)
    mv s4, t5
    ld t5, 40(sp)
    mv s5, t5
    ld t5, 24(sp)
    mv s6, t5
    mv s7, t3
    j .Lfoo_0
.Lfoo_1:
    mv s5, t0
    mv t0, t1
    mv t1, t2
    mv s6, t2
    mv t2, t3
.Lfoo_2:
    slt s7, t1, s5
    sltu s8, t3, s7
    xor s9, t2, t3
    seqz s9, s9
    and s10, s8, s9
    beqz s10, .Lfoo_3
    addw s11, t1, s3
    mv s4, t1
    sll t4, s4, s2
    sd t4, 48(sp)
    ld t6, 48(sp)
    add t4, t0, t6
    sd t4, 56(sp)
    ld t5, 56(sp)
    lw t4, 0(t5)
    sd t4, 64(sp)
    ld t6, 64(sp)
    addw t4, s6, t6
    sd t4, 72(sp)
    mv t4, s5
    sd t4, 80(sp)
    mv t4, t0
    sd t4, 88(sp)
    ld t5, 80(sp)
    mv s5, t5
    ld t5, 88(sp)
    mv t0, t5
    mv t1, s11
    ld t5, 72(sp)
    mv s6, t5
    mv t2, t3
    j .Lfoo_2
.Lfoo_3:
    mv t0, s6
    mv a0, t0
    ld s2, 96(sp)
    ld s3, 104(sp)
    ld s4, 112(sp)
    ld s5, 120(sp)
    ld s6, 128(sp)
    ld s7, 136(sp)
    ld s8, 144(sp)
    ld s9, 152(sp)
    ld s10, 160(sp)
    ld s11, 168(sp)
    addi sp, sp, 240
    ret
.size foo, .-foo
