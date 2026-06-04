.text
.globl foo
.type foo, @function
foo:
    mv t0, a0
    la t1, g
    mv t2, t0
    add t0, t1, t2
    lb t1, 0(t0)
    andi t0, t1, 255
    mv a0, t0
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
