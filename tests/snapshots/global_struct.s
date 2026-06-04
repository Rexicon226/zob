.text
.globl foo
.type foo, @function
foo:
    addi sp, sp, -16
    sd s2, 0(sp)
    la t0, s
    lw t1, 0(t0)
    li t2, 4
    add t3, t0, t2
    lb s2, 0(t3)
    andi t3, s2, 255
    addw s2, t1, t3
    li t3, 16
    add t1, t0, t3
    lw t3, 0(t1)
    addw t0, s2, t3
    add t3, t1, t2
    lb t2, 0(t3)
    andi t3, t2, 255
    addw t2, t0, t3
    mv a0, t2
    ld s2, 0(sp)
    addi sp, sp, 16
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
