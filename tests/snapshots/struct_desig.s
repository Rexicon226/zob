.text
.globl foo
.type foo, @function
foo:
    li t1, 250
    mv a0, t1
    ret
.size foo, .-foo
