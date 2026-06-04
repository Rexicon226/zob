.text
.globl foo
.type foo, @function
foo:
    mv t0, a0
    la t1, y
    li t2, 10
    addw t3, t0, t2
    sw t3, 0(t1)
    mv a0, t3
    ret
.size foo, .-foo
.bss
.globl y
.type y, @object
.align 2
y:
    .zero 4
.size y, 4
