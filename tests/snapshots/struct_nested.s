.text
.globl foo
.type foo, @function
foo:
    li t0, 123
    mv a0, t0
    ret
.size foo, .-foo
