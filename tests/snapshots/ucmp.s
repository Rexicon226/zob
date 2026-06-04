.text
.globl foo
.type foo, @function
foo:
    mv t0, a0
    li t1, 5
    sltu t2, t1, t0
    mv a0, t2
    ret
.size foo, .-foo
