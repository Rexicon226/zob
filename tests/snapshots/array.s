.text
.globl foo
.type foo, @function
foo:
    mv t0, a0
    li t1, 1
    addw t2, t0, t1
    addw t3, t0, t2
    addw t2, t0, t3
    subw t3, t2, t1
    mv a0, t3
    ret
.size foo, .-foo
