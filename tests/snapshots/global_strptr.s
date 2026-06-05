.text
.globl foo
.type foo, @function
foo:
    li t0, -16
    add sp, sp, t0
    sd s2, 0(sp)
    mv t1, a0
    la t2, names
    mv t3, t1
    li t1, 3
    sll s2, t3, t1
    add t1, t2, s2
    ld t2, 0(t1)
    lb t1, 0(t2)
    andi t2, t1, 255
    mv a0, t2
    ld s2, 0(sp)
    li t0, 16
    add sp, sp, t0
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
