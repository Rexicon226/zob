.text
.globl foo
.type foo, @function
foo:
    mv t1, a0
    li t2, 10
    sw t2, 0(t1)
    li t3, 20
    sw t3, 0(t1)
    mv a0, t2
    ret
.size foo, .-foo
