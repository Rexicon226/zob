.text
.globl foo
.type foo, @function
foo:
    mv t0, a0
    mv t1, a1
    li t2, 0
    sltu t3, t2, t0
    beqz t3, .Lfoo_0
    li t3, 1
    mv t0, t3
    j .Lfoo_1
.Lfoo_0:
    sltu t3, t2, t1
    mv t0, t3
.Lfoo_1:
    mv a0, t0
    ret
.size foo, .-foo
