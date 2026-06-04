.text
.globl foo
.type foo, @function
foo:
    mv t0, a0
    li t1, 5
    addw t2, t0, t1
    li t1, 2
    subw t0, t2, t1
    li t2, 3
    mulw t3, t0, t2
    divw t2, t3, t1
    li t1, 17
    remw t3, t2, t1
    mv a0, t3
    ret
.size foo, .-foo
