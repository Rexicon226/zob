.text
.globl foo
.type foo, @function
foo:
    addi sp, sp, -80
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
    mv t0, a1
    mv t1, a0
    li t2, 0
    li t3, 0
    mv s2, t0
    mv t0, t2
    mv t2, t1
    mv s3, t3
.Lfoo_0:
    slt s4, t0, s2
    sltu s5, t3, s4
    xor s6, s3, t3
    seqz s6, s6
    and s7, s5, s6
    beqz s7, .Lfoo_1
    sw t0, 0(t2)
    li s8, 1
    addw s9, t0, s8
    mv s10, s2
    mv s11, t2
    mv s2, s10
    mv t0, s9
    mv t2, s11
    mv s3, t3
    j .Lfoo_0
.Lfoo_1:
    lw t0, 0(t1)
    mv a0, t0
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
    addi sp, sp, 80
    ret
.size foo, .-foo
