.text
.globl foo
.type foo, @function
foo:
    li t0, -112
    add sp, sp, t0
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
    mv t1, a0
    li t2, 0
    li t3, 0
    li s2, 1
    mv s3, t1
    mv t1, t2
    mv s4, t2
    mv t2, t3
    mv s5, s2
.Lfoo_0:
    beqz s5, .Lfoo_2
    mv s6, s2
    j .Lfoo_3
.Lfoo_2:
    slt s7, s4, s3
    sltu s8, t3, s7
    mv s6, s8
.Lfoo_3:
    xor s9, t2, t3
    seqz s9, s9
    and s10, s6, s9
    beqz s10, .Lfoo_1
    li s11, 1
    addw t4, s4, s11
    sd t4, 0(sp)
    ld t6, 0(sp)
    addw t4, t1, t6
    sd t4, 8(sp)
    mv t4, s3
    sd t4, 16(sp)
    ld t5, 16(sp)
    mv s3, t5
    ld t5, 8(sp)
    mv t1, t5
    ld t5, 0(sp)
    mv s4, t5
    mv t2, t3
    mv s5, t3
    j .Lfoo_0
.Lfoo_1:
    mv t3, t1
    mv a0, t3
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
    li t0, 112
    add sp, sp, t0
    ret
.size foo, .-foo
