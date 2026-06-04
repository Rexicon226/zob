.text
.globl foo
.type foo, @function
foo:
    mv t0, a0
    la t1, names
    mv t2, t0
    li t0, 3
    sll t3, t2, t0
    add t0, t1, t3
    ld t1, 0(t0)
    lb t0, 0(t1)
    andi t1, t0, 255
    mv a0, t1
    ret
.size foo, .-foo
.data
.type .Lstr0, @object
.align 0
.Lstr0:
    .byte 97
    .byte 98
    .byte 99
    .byte 0
.size .Lstr0, 4
.data
.type .Lstr1, @object
.align 0
.Lstr1:
    .byte 98
    .byte 99
    .byte 100
    .byte 0
.size .Lstr1, 4
.data
.type .Lstr2, @object
.align 0
.Lstr2:
    .byte 99
    .byte 100
    .byte 101
    .byte 0
.size .Lstr2, 4
.data
.globl names
.type names, @object
.align 3
names:
    .quad .Lstr0
    .quad .Lstr1
    .quad .Lstr2
.size names, 24
