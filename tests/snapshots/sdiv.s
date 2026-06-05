.text
.globl foo
.type foo, @function
foo:
    mv t1, a0
    li t2, 2
    divw t3, t1, t2
    mv a0, t3
    ret
.size foo, .-foo
