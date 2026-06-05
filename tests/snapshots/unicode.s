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
    mv t1, a1
    mv t2, a0
    li t3, 0
    li s2, 127
    sltu s3, s2, t1
    xor s2, s3, t3
    seqz s2, s2
    sltu s3, t3, s2
    beqz s3, .Lfoo_0
    slli s2, t1, 56
    srai s2, s2, 56
    sb s2, 0(t2)
    li s2, 1
    mv s4, s2
    j .Lfoo_1
.Lfoo_0:
    xor s2, s3, t3
    seqz s2, s2
    li s3, 2047
    sltu s5, s3, t1
    xor s3, s5, t3
    seqz s3, s3
    sltu s5, t3, s3
    and s3, s2, s5
    li s6, 6
    srlw s7, t1, s6
    li s6, 1
    add s8, t2, s6
    li s6, 63
    and s9, t1, s6
    li s10, 128
    or s11, s9, s10
    slli s9, s11, 56
    srai s9, s9, 56
    beqz s3, .Lfoo_2
    li s11, 192
    or s3, s7, s11
    slli s11, s3, 56
    srai s11, s11, 56
    sb s11, 0(t2)
    sb s9, 0(s8)
    li s11, 2
    mv s3, s11
    j .Lfoo_3
.Lfoo_2:
    xor s11, s5, t3
    seqz s11, s11
    and s5, s2, s11
    li s11, 65535
    sltu s2, s11, t1
    xor s11, s2, t3
    seqz s11, s11
    sltu s2, t3, s11
    and s11, s5, s2
    li s5, 12
    srlw s2, t1, s5
    and s5, s7, s6
    or s7, s5, s10
    slli s5, s7, 56
    srai s5, s5, 56
    li s7, 2
    add t3, t2, s7
    beqz s11, .Lfoo_4
    li s7, 224
    or s11, s2, s7
    slli s7, s11, 56
    srai s7, s7, 56
    sb s7, 0(t2)
    sb s5, 0(s8)
    sb s9, 0(t3)
    li s7, 3
    mv s11, s7
    j .Lfoo_5
.Lfoo_4:
    li s7, 18
    srlw t4, t1, s7
    sd t4, 0(sp)
    li s7, 240
    ld t5, 0(sp)
    or t1, t5, s7
    slli s7, t1, 56
    srai s7, s7, 56
    sb s7, 0(t2)
    and s7, s2, s6
    or s2, s7, s10
    slli s7, s2, 56
    srai s7, s7, 56
    sb s7, 0(s8)
    sb s5, 0(t3)
    li s2, 3
    add s5, t2, s2
    sb s9, 0(s5)
    li s9, 4
    mv s11, s9
.Lfoo_5:
    mv s3, s11
.Lfoo_3:
    mv s4, s3
.Lfoo_1:
    mv a0, s4
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
