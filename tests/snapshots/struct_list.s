.text
.globl foo
.type foo, @function
foo:
    li t0, -16
    add sp, sp, t0
    li t0, 0
    add t1, sp, t0
    li t2, 42
    sw t2, 0(t1)
    mv a0, t2
    li t0, 16
    add sp, sp, t0
    ret
.size foo, .-foo
