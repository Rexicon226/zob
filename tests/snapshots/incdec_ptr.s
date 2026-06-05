.text
.globl foo
.type foo, @function
foo:
    mv t1, a0
    li t2, 3
    sw t2, 0(t1)
    li t2, 4
    add t3, t1, t2
    li t2, 4
    sw t2, 0(t3)
    lw t3, 0(t1)
    addw t1, t3, t2
    mv a0, t1
    ret
.size foo, .-foo
