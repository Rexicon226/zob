.text
.globl foo
.type foo, @function
foo:
    li t0, 14
    mv a0, t0
    ret
.size foo, .-foo
