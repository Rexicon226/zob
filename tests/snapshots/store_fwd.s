.text
.globl foo
.type foo, @function
foo:
    mv t0, a0
    li t1, 5
    mulw t2, t0, t1
    mv a0, t2
    ret
.size foo, .-foo
