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
    mv t0, a0
    li t1, 0
    li t2, 0
    mv t3, t0
    mv t0, t1
    mv t1, t2
.Lfoo_0:
    xor s2, t1, t2
    seqz s2, s2
    beqz s2, .Lfoo_1
    xor s3, t3, t0
    seqz s3, s3
    sltu s4, t2, s3
    beqz s4, .Lfoo_2
    mv s5, t0
    j .Lfoo_3
.Lfoo_2:
    li s6, 1
    addw s7, t0, s6
    mv s5, s7
.Lfoo_3:
    mv s8, t3
    mv t3, s8
    mv t0, s5
    mv t1, s4
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
    addi sp, sp, 64
    ret
.size foo, .-foo
