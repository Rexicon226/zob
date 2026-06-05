.text
.globl foo
.type foo, @function
foo:
    mv t1, a0
    li t2, 60
    and t3, t1, t2
    li t2, 128
    or t1, t3, t2
    li t2, 168
    xor t3, t1, t2
    li t2, 2
    sllw t1, t3, t2
    li t2, 1
    sraw t3, t1, t2
    mv a0, t3
    ret
.size foo, .-foo
