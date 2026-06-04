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
    addw s7, t0, s2
    li s8, 1
    addw s9, s2, s8
    mv s10, t3
    mv t3, s10
    mv t0, s7
    mv s2, s9
    mv t1, t2
    j .Lfoo_0
.Lfoo_1:
    mv t2, t0
    mv a0, t2
    ld s2, 0(sp)
    ld s3, 8(sp)
    ld s4, 16(sp)
    ld s5, 24(sp)
    ld s6, 32(sp)
    ld s7, 40(sp)
    ld s8, 48(sp)
    ld s9, 56(sp)
    ld s10, 64(sp)
    addi sp, sp, 80
    ret
.size foo, .-foo
