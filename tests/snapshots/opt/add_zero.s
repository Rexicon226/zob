.text
.globl foo
.type foo, @function
foo:
    mv t0, a0
    mv a0, t0
    ret
.size foo, .-foo
