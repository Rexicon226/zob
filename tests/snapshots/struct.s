.text
.globl foo
.type foo, @function
foo:
    mv t0, a0
    mv t1, a1
    li t2, 10
    mulw t3, t0, t2
    addw t2, t3, t1
    mv a0, t2
    ret
.size foo, .-foo
