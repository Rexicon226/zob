.text
.globl foo
.type foo, @function
foo:
    mv t0, a0
    li t1, 10
    sw t1, 0(t0)
    li t2, 20
    sw t2, 0(t0)
    mv a0, t1
    ret
.size foo, .-foo
