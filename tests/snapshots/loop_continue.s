.text
.globl foo
.type foo, @function
foo:
    addi sp, sp, -112
    sd s2, 24(sp)
    sd s3, 32(sp)
    sd s4, 40(sp)
    sd s5, 48(sp)
    sd s6, 56(sp)
    sd s7, 64(sp)
    sd s8, 72(sp)
    sd s9, 80(sp)
    sd s10, 88(sp)
    sd s11, 96(sp)
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
    li s7, 2
    xor s8, s2, s7
    seqz s8, s8
    sltu s9, t2, s8
    beqz s9, .Lfoo_2
    mv s10, t0
    j .Lfoo_3
.Lfoo_2:
    addw s11, t0, s2
    mv s10, s11
.Lfoo_3:
    li t4, 1
    sd t4, 0(sp)
    ld t6, 0(sp)
    addw t4, s2, t6
    sd t4, 8(sp)
    mv t4, t3
    sd t4, 16(sp)
    ld t5, 16(sp)
    mv t3, t5
    mv t0, s10
    ld t5, 8(sp)
    mv s2, t5
    mv t1, t2
    j .Lfoo_0
.Lfoo_1:
    mv t2, t0
    mv a0, t2
    ld s2, 24(sp)
    ld s3, 32(sp)
    ld s4, 40(sp)
    ld s5, 48(sp)
    ld s6, 56(sp)
    ld s7, 64(sp)
    ld s8, 72(sp)
    ld s9, 80(sp)
    ld s10, 88(sp)
    ld s11, 96(sp)
    addi sp, sp, 112
    ret
.size foo, .-foo
