.text
.globl foo
.type foo, @function
foo:
    li t0, -16
    add sp, sp, t0
    sd s2, 0(sp)
    sd s3, 8(sp)
    la t1, s
    lw t2, 0(t1)
    li t3, 4
    add s2, t1, t3
    lb s3, 0(s2)
    andi s2, s3, 255
    addw s3, t2, s2
    li s2, 16
    add t2, t1, s2
    lw s2, 0(t2)
    addw t1, s3, s2
    add s2, t2, t3
    lb t3, 0(s2)
    andi s2, t3, 255
    addw t3, t1, s2
    mv a0, t3
    ld s2, 0(sp)
    ld s3, 8(sp)
    li t0, 16
    add sp, sp, t0
    ret
.size foo, .-foo
.data
.globl s
.type s, @object
.align 3
s:
    .byte 10
    .byte 0
    .byte 0
    .byte 0
    .byte 0
    .byte 0
    .byte 0
    .byte 0
    .byte 0
    .byte 0
    .byte 0
    .byte 0
    .byte 0
    .byte 0
    .byte 0
    .byte 0
    .byte 0
    .byte 0
    .byte 0
    .byte 0
    .byte 20
    .byte 0
    .byte 0
    .byte 0
    .byte 0
    .byte 0
    .byte 0
    .byte 0
    .byte 0
    .byte 0
    .byte 0
    .byte 0
.size s, 32
