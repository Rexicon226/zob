.text
.globl foo
.type foo, @function
foo:
    mv t1, a0
    slli t2, t1, 48
    srai t2, t2, 48
    mv t1, t2
    mv a0, t1
    ret
.size foo, .-foo
