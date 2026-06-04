.text
.globl foo
.type foo, @function
foo:
    addi sp, sp, -96
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
    mv t0, a0
    mv t1, a1
    li t2, 0
    li t3, 0
    mv s2, t0
    mv t0, t2
    mv s3, t2
    mv t2, t1
    mv t1, t3
.Lfoo_0:
    slt s4, s3, t2
    sltu s5, t3, s4
    xor s6, t1, t3
    seqz s6, s6
    and s7, s5, s6
    beqz s7, .Lfoo_1
    addw s8, s2, t0
    li s9, 1
    addw s10, s3, s9
    mv s11, s2
    mv t4, t2
    sd t4, 0(sp)
    mv s2, s11
    mv t0, s8
    mv s3, s10
    ld t5, 0(sp)
    mv t2, t5
    mv t1, t3
    j .Lfoo_0
.Lfoo_1:
    mv s3, t0
    mv a0, s3
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
    addi sp, sp, 96
    ret
.size foo, .-foo
