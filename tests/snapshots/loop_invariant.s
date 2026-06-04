.text
.globl foo
.type foo, @function
foo:
    mv t0, a0
    li t1, 42
    sw t1, 0(t0)
    mv a0, t1
    ret
.size foo, .-foo
