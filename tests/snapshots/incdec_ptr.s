.text
.globl foo
.type foo, @function
foo:
    mv t0, a0
    li t1, 3
    sw t1, 0(t0)
    li t1, 4
    add t2, t0, t1
    li t1, 4
    sw t1, 0(t2)
    lw t2, 0(t0)
    addw t0, t2, t1
    mv a0, t0
    ret
.size foo, .-foo
