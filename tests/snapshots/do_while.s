.text
.globl foo
.type foo, @function
foo:
    addi sp, sp, -96
    sd s2, 16(sp)
    sd s3, 24(sp)
    sd s4, 32(sp)
    sd s5, 40(sp)
    sd s6, 48(sp)
    sd s7, 56(sp)
    sd s8, 64(sp)
    sd s9, 72(sp)
    sd s10, 80(sp)
    sd s11, 88(sp)
    mv t0, a0
    li t1, 0
    li t2, 0
    li t3, 1
    mv s2, t0
    mv t0, t1
    mv s3, t1
    mv t1, t2
    mv s4, t3
.Lfoo_0:
    beqz s4, .Lfoo_2
    mv s5, t3
    j .Lfoo_3
.Lfoo_2:
    slt s6, s3, s2
    sltu s7, t2, s6
    mv s5, s7
.Lfoo_3:
    xor s8, t1, t2
    seqz s8, s8
    and s9, s5, s8
    beqz s9, .Lfoo_1
    li s10, 1
    addw s11, s3, s10
    addw t4, t0, s11
    sd t4, 0(sp)
    mv t4, s2
    sd t4, 8(sp)
    ld t5, 8(sp)
    mv s2, t5
    ld t5, 0(sp)
    mv t0, t5
    mv s3, s11
    mv t1, t2
    mv s4, t2
    j .Lfoo_0
.Lfoo_1:
    mv t2, t0
    mv a0, t2
    ld s2, 16(sp)
    ld s3, 24(sp)
    ld s4, 32(sp)
    ld s5, 40(sp)
    ld s6, 48(sp)
    ld s7, 56(sp)
    ld s8, 64(sp)
    ld s9, 72(sp)
    ld s10, 80(sp)
    ld s11, 88(sp)
    addi sp, sp, 96
    ret
.size foo, .-foo
