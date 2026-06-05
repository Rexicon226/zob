.text
.globl foo
.type foo, @function
foo:
    mv t1, a0
    li t2, 0
    sltu t3, t2, t1
    beqz t3, .Lfoo_0
    li t2, 10
    mv t3, t2
    j .Lfoo_1
.Lfoo_0:
    li t2, 20
    mv t3, t2
.Lfoo_1:
    mv a0, t3
    ret
.size foo, .-foo
