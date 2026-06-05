.text
.globl foo
.type foo, @function
foo:
    la t1, y
    lw t2, 0(t1)
    mv a0, t2
    ret
.size foo, .-foo
.data
.globl y
.type y, @object
.align 2
y:
    .byte 10
    .byte 0
    .byte 0
    .byte 0
.size y, 4
