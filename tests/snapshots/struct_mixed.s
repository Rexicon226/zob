.text
.globl foo
.type foo, @function
foo:
    li t1, 1007
    mv a0, t1
    ret
.size foo, .-foo
