.text
.globl foo
.type foo, @function
foo:
    mv t1, a0
    li t2, 5
    sltu t3, t2, t1
    mv a0, t3
    ret
.size foo, .-foo
