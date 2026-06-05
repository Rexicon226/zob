.text
.globl foo
.type foo, @function
foo:
    mv t1, a0
    slli t2, t1, 56
    srai t2, t2, 56
    andi t1, t2, 255
    mv a0, t1
    ret
.size foo, .-foo
