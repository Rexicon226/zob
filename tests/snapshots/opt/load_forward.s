.text
.globl foo
.type foo, @function
foo:
    mv t1, a0
    mulw t2, t1, t1
    mv a0, t2
    ret
.size foo, .-foo
