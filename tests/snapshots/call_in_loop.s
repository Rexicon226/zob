.text
.globl inc
.type inc, @function
inc:
    mv t0, a0
    li t1, 1
    addw t2, t0, t1
    mv a0, t2
    ret
.size inc, .-inc
.text
.globl foo
.type foo, @function
foo:
    addi sp, sp, -96
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
    sd ra, 80(sp)
    mv t0, a0
    li t1, 0
    li s2, 0
    mv s3, t0
    mv s4, t1
    mv s5, t1
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
    mv t1, a0
    mv t0, t1
    li t2, 1
    addw t3, s5, t2
    mv s11, s3
    mv s3, s11
    mv s4, t0
    mv s5, t3
    mv s6, s2
    j .Lfoo_0
.Lfoo_1:
    mv s2, s4
    mv a0, s2
    ld ra, 80(sp)
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
    addi sp, sp, 96
    ret
.size foo, .-foo
