.text
.globl inc
.type inc, @function
inc:
    mv t1, a0
    li t2, 1
    addw t3, t1, t2
    mv a0, t3
    ret
.size inc, .-inc
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
    sd ra, 88(sp)
    mv t1, a0
    li t2, 0
    li s2, 0
    mv s3, t1
    mv s4, t2
    mv s5, t2
    mv s6, s2
.Lfoo_0:
    slt s7, s5, s3
    sltu s8, s2, s7
    xor s9, s6, s2
    seqz s9, s9
    and s10, s8, s9
    beqz s10, .Lfoo_1
    mv a0, s4
    call inc
    mv t2, a0
    mv t1, t2
    li t3, 1
    addw s11, s5, t3
    mv t4, s3
    sd t4, 0(sp)
    ld t5, 0(sp)
    mv s3, t5
    mv s4, t1
    mv s5, s11
    mv s6, s2
    j .Lfoo_0
.Lfoo_1:
    mv s2, s4
    mv a0, s2
    ld ra, 88(sp)
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
