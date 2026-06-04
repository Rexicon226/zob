.text
.globl foo
.type foo, @function
foo:
    addi sp, sp, -64
    sd s2, 0(sp)
    sd s3, 8(sp)
    sd s4, 16(sp)
    sd s5, 24(sp)
    sd s6, 32(sp)
    sd s7, 40(sp)
    sd s8, 48(sp)
    sd s9, 56(sp)
    li t0, 0
    li t1, 0
    mv t2, t0
    mv t3, t0
    mv t0, t1
.Lfoo_0:
    li s2, 10
    slt s3, t3, s2
    sltu s4, t1, s3
    xor s5, t0, t1
    seqz s5, s5
    and s6, s4, s5
    beqz s6, .Lfoo_1
    addw s7, t2, t3
    li s8, 1
    addw s9, t3, s8
    mv t2, s7
    mv t3, s9
    mv t0, t1
    j .Lfoo_0
.Lfoo_1:
    mv t1, t2
    mv a0, t1
    ld s2, 0(sp)
    ld s3, 8(sp)
    ld s4, 16(sp)
    ld s5, 24(sp)
    ld s6, 32(sp)
    ld s7, 40(sp)
    ld s8, 48(sp)
    ld s9, 56(sp)
    addi sp, sp, 64
    ret
.size foo, .-foo
