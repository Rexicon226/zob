.text
.globl foo
.type foo, @function
foo:
    mv t1, a0
    la t2, g
    mv t3, t1
    add t1, t2, t3
    lb t2, 0(t1)
    andi t1, t2, 255
    mv a0, t1
    ret
.size foo, .-foo
.data
.globl g
.type g, @object
.align 0
g:
    .byte 111
    .byte 107
    .byte 0
.size g, 3
