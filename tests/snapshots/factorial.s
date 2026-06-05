.text
.globl foo
.type foo, @function
foo:
    li t0, -96
    add sp, sp, t0
    sd s2, 8(sp)
    sd s3, 16(sp)
    sd s4, 24(sp)
    sd s5, 32(sp)
    sd s6, 40(sp)
    sd s7, 48(sp)
    sd s8, 56(sp)
    sd s9, 64(sp)
    sd s10, 72(sp)
    sd s11, 80(sp)
    mv t1, a0
    li t2, 1
    li t3, 0
    mv s2, t1
    mv t1, t2
    mv s3, t2
    mv s4, t3
.Lfoo_0:
    addw s5, s2, t2
    slt s6, t1, s5
    sltu s7, t3, s6
    xor s8, s4, t3
    seqz s8, s8
    and s9, s7, s8
    beqz s9, .Lfoo_1
    addw s10, t1, t2
    mulw s11, t1, s3
    mv t4, s2
    sd t4, 0(sp)
    ld t5, 0(sp)
    mv s2, t5
    mv t1, s10
    mv s3, s11
    mv s4, t3
    j .Lfoo_0
.Lfoo_1:
    mv t3, s3
    mv a0, t3
    ld s2, 8(sp)
    ld s3, 16(sp)
    ld s4, 24(sp)
    ld s5, 32(sp)
    ld s6, 40(sp)
    ld s7, 48(sp)
    ld s8, 56(sp)
    ld s9, 64(sp)
    ld s10, 72(sp)
    ld s11, 80(sp)
    li t0, 96
    add sp, sp, t0
    ret
.size foo, .-foo
