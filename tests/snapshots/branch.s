.text
.globl foo
.type foo, @function
foo:
    mv t0, a0
    mv t1, a1
    li t2, 0
    sltu t3, t2, t0
    beqz t3, .Lfoo_0
    li t2, 30
    sw t2, 0(t1)
    li t2, 10
    mv t1, t2
    j .Lfoo_1
.Lfoo_0:
    li t2, 20
    mv t1, t2
.Lfoo_1:
    mv a0, t1
    ret
.size foo, .-foo
