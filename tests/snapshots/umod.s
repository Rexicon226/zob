.text
.globl foo
.type foo, @function
foo:
    li t1, 1
    mv a0, t1
    ret
.size foo, .-foo
