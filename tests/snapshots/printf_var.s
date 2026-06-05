.text
.globl foo
.type foo, @function
foo:
    li t0, -16
    add sp, sp, t0
    sd ra, 0(sp)
    mv t1, a0
    la t2, .Lstr3
    mv a0, t2
    mv a1, t1
    call printf
    mv t2, a0
    mv t1, t2
    mv a0, t1
    ld ra, 0(sp)
    li t0, 16
    add sp, sp, t0
    ret
.size foo, .-foo
.data
.type .Lstr3, @object
.align 0
.Lstr3:
    .byte 115
    .byte 111
    .byte 109
    .byte 101
    .byte 116
    .byte 104
    .byte 105
    .byte 110
    .byte 103
    .byte 32
    .byte 37
    .byte 100
    .byte 10
    .byte 0
.size .Lstr3, 14
