.text
.globl foo
.type foo, @function
foo:
    mv t1, a0
    mv a0, t1
    ret
.size foo, .-foo
