.text
.globl foo
.type foo, @function
foo:
    mv t0, a0
    li t1, 0
    li t2, 0
    slt t3, t2, t0
    sltu t2, t1, t3
    beqz t2, .Lfoo_0
    li t2, 10
    slt t3, t0, t2
    sltu t2, t1, t3
    mv t3, t2
    j .Lfoo_1
.Lfoo_0:
    mv t3, t1
.Lfoo_1:
    mv a0, t3
    ret
.size foo, .-foo
