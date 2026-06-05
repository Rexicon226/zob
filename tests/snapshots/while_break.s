.text
.globl foo
.type foo, @function
foo:
    li t0, -64
    add sp, sp, t0
    sd s2, 0(sp)
    sd s3, 8(sp)
    sd s4, 16(sp)
    sd s5, 24(sp)
    sd s6, 32(sp)
    sd s7, 40(sp)
    sd s8, 48(sp)
    sd s9, 56(sp)
    mv t1, a0
    li t2, 0
    li t3, 0
    mv s2, t1
    mv t1, t2
    mv t2, t3
.Lfoo_0:
    xor s3, t2, t3
    seqz s3, s3
    beqz s3, .Lfoo_1
    xor s4, s2, t1
    seqz s4, s4
    sltu s5, t3, s4
    beqz s5, .Lfoo_2
    mv s6, t1
    j .Lfoo_3
.Lfoo_2:
    li s7, 1
    addw s8, t1, s7
    mv s6, s8
.Lfoo_3:
    mv s9, s2
    mv s2, s9
    mv t1, s6
    mv t2, s5
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
    li t0, 64
    add sp, sp, t0
    ret
.size foo, .-foo
