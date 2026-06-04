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
    li t3, 127
    sltu s2, t3, t0
    xor t3, s2, t2
    seqz t3, t3
    sltu s2, t2, t3
    beqz s2, .Lfoo_0
    slli t3, t0, 56
    srai t3, t3, 56
    sb t3, 0(t1)
    li t3, 1
    mv s3, t3
    j .Lfoo_1
.Lfoo_0:
    xor t3, s2, t2
    seqz t3, t3
    li s2, 2047
    sltu s4, s2, t0
    xor s2, s4, t2
    seqz s2, s2
    sltu s4, t2, s2
    and s2, t3, s4
    li s5, 6
    srlw s6, t0, s5
    li s5, 1
    add s7, t1, s5
    li s5, 63
    and s8, t0, s5
    li s9, 128
    or s10, s8, s9
    slli s8, s10, 56
    srai s8, s8, 56
    beqz s2, .Lfoo_2
    li s10, 192
    or s2, s6, s10
    slli s10, s2, 56
    srai s10, s10, 56
    sb s10, 0(t1)
    sb s8, 0(s7)
    li s10, 2
    mv s2, s10
    j .Lfoo_3
.Lfoo_2:
    xor s10, s4, t2
    seqz s10, s10
    and s4, t3, s10
    li s10, 65535
    sltu t3, s10, t0
    xor s10, t3, t2
    seqz s10, s10
    sltu t3, t2, s10
    and s10, s4, t3
    li s4, 12
    srlw t3, t0, s4
    and s4, s6, s5
    or s6, s4, s9
    slli s4, s6, 56
    srai s4, s4, 56
    li s6, 2
    add t2, t1, s6
    beqz s10, .Lfoo_4
    li s6, 224
    or s10, t3, s6
    slli s6, s10, 56
    srai s6, s6, 56
    sb s6, 0(t1)
    sb s4, 0(s7)
    sb s8, 0(t2)
    li s6, 3
    mv s10, s6
    j .Lfoo_5
.Lfoo_4:
    li s6, 18
    srlw s11, t0, s6
    li s6, 240
    or t0, s11, s6
    slli s6, t0, 56
    srai s6, s6, 56
    sb s6, 0(t1)
    and s6, t3, s5
    or t3, s6, s9
    slli s6, t3, 56
    srai s6, s6, 56
    sb s6, 0(s7)
    sb s4, 0(t2)
    li t3, 3
    add s4, t1, t3
    sb s8, 0(s4)
    li s8, 4
    mv s10, s8
.Lfoo_5:
    mv s2, s10
.Lfoo_3:
    mv s3, s2
.Lfoo_1:
    mv a0, s3
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
