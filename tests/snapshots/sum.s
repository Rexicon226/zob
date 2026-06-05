.text
.globl foo
.type foo, @function
foo:
    li t0, -80
    add sp, sp, t0
    sd s2, 0(sp)
    sd s3, 8(sp)
    sd s4, 16(sp)
    sd s5, 24(sp)
    sd s6, 32(sp)
    sd s7, 40(sp)
    sd s8, 48(sp)
    sd s9, 56(sp)
    sd s10, 64(sp)
    sd s11, 72(sp)
    mv t1, a0
    li t2, 0
    li t3, 0
    mv s2, t1
    mv t1, t2
    mv s3, t2
    mv t2, t3
.Lfoo_0:
    slt s4, s3, s2
    sltu s5, t3, s4
    xor s6, t2, t3
    seqz s6, s6
    and s7, s5, s6
    beqz s7, .Lfoo_1
    addw s8, t1, s3
    li s9, 1
    addw s10, s3, s9
    mv s11, s2
    mv s2, s11
    mv t1, s8
    mv s3, s10
    mv t2, t3
    j .Lfoo_0
.Lfoo_1:
    mv t3, t1
    mv a0, t3
    ld s2, 0(sp)
    ld s3, 8(sp)
    ld s4, 16(sp)
    ld s5, 24(sp)
    ld s6, 32(sp)
    ld s7, 40(sp)
    ld s8, 48(sp)
    ld s9, 56(sp)
    ld s10, 64(sp)
    ld s11, 72(sp)
    li t0, 80
    add sp, sp, t0
    ret
.size foo, .-foo
