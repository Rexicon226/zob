.text
.globl foo
.type foo, @function
foo:
    addi sp, sp, -16
    sd ra, 0(sp)
    mv t0, a0
    la t1, .Lstr3
    mv a0, t1
    mv a1, t0
    call printf
    mv t1, a0
    mv t0, t1
    mv a0, t0
    ld ra, 0(sp)
    addi sp, sp, 16
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
