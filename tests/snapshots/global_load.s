.text
.globl foo
.type foo, @function
foo:
    la t0, y
    lw t1, 0(t0)
    mv a0, t1
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
