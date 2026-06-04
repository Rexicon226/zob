.text
.globl foo
.type foo, @function
foo:
    mv t0, a0
    li t1, 1
    addw t2, t0, t1
    addw t3, t2, t1
    addw t2, t3, t0
    addw t1, t3, t2
    addw t2, t0, t1
    addw t1, t0, t2
    mv a0, t1
    ret
.size foo, .-foo
