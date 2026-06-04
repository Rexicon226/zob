.text
.globl foo
.type foo, @function
foo:
    mv t0, a0
    li t1, 1
    addw t2, t0, t1
    addw t0, t2, t1
    sllw t2, t0, t1
    mv a0, t2
    ret
.size foo, .-foo
