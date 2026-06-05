.text
.globl foo
.type foo, @function
foo:
    li t0, -16
    add sp, sp, t0
    sd s2, 0(sp)
    mv t1, a0
    la t2, y
    li t3, 10
    addw s2, t1, t3
    sw s2, 0(t2)
    mv a0, s2
    ld s2, 0(sp)
    li t0, 16
    add sp, sp, t0
    ret
.size foo, .-foo
.bss
.globl y
.type y, @object
.align 2
y:
    .zero 4
.size y, 4
