.text
.globl foo
.type foo, @function
foo:
    mv t0, a0
    mulw t1, t0, t0
    mv a0, t1
    ret
.size foo, .-foo
