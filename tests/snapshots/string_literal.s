.text
.globl foo
.type foo, @function
foo:
    mv t0, a0
    la t1, .Lstr0
    mv t2, t0
    add t0, t1, t2
    lb t1, 0(t0)
    andi t0, t1, 255
    mv a0, t0
    ret
.size foo, .-foo
.data
.type .Lstr0, @object
.align 0
.Lstr0:
    .byte 104
    .byte 105
    .byte 0
.size .Lstr0, 3
