.text
.globl foo
.type foo, @function
foo:
    mv t1, a0
    la t2, .Lstr0
    mv t3, t1
    add t1, t2, t3
    lb t2, 0(t1)
    andi t1, t2, 255
    mv a0, t1
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
