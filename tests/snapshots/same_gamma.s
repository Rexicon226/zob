.text
.globl foo
.type foo, @function
foo:
    li t0, 5
    mv a0, t0
    ret
.size foo, .-foo
