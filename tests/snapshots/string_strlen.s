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
    la t0, .Lstr0
    li t1, 0
    li t2, 0
    mv t3, t0
    mv t0, t1
    mv t1, t2
.Lfoo_0:
    mv s2, t0
    add s3, t3, s2
    lb s4, 0(s3)
    andi s5, s4, 255
    sltu s6, t2, s5
    xor s7, t1, t2
    seqz s7, s7
    and s8, s6, s7
    beqz s8, .Lfoo_1
    li s9, 1
    addw s10, t0, s9
    mv s11, t3
    mv t3, s11
    mv t0, s10
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
    ld s11, 72(sp)
    addi sp, sp, 80
    ret
.size foo, .-foo
.data
.type .Lstr0, @object
.align 0
.Lstr0:
    .byte 104
    .byte 101
    .byte 108
    .byte 108
    .byte 111
    .byte 0
.size .Lstr0, 6
