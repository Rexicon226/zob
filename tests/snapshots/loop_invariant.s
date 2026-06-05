.text
.globl foo
.type foo, @function
foo:
    mv t1, a0
    li t2, 42
    sw t2, 0(t1)
    mv a0, t2
    ret
.size foo, .-foo
