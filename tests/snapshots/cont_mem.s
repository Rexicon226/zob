.text
.globl foo
.type foo, @function
foo:
    mv t0, a0
    mv t1, a1
    li t2, 0
    sltu t3, t2, t0
    beqz t3, .Lfoo_0
    li t2, 1
    sw t2, 0(t1)
    j .Lfoo_1
.Lfoo_0:
    li t2, 2
    sw t2, 0(t1)
.Lfoo_1:
    lw t2, 0(t1)
    mv a0, t2
    ret
.size foo, .-foo
