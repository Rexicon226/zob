.text
.globl foo
.type foo, @function
foo:
    mv t0, a0
    li t1, 0
    sltu t2, t1, t0
    beqz t2, .Lfoo_0
    li t1, 10
    mv t2, t1
    j .Lfoo_1
.Lfoo_0:
    li t1, 20
    mv t2, t1
.Lfoo_1:
    mv a0, t2
    ret
.size foo, .-foo
