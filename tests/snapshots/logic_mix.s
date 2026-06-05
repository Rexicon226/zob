.text
.globl foo
.type foo, @function
foo:
    li t0, -16
    add sp, sp, t0
    sd s2, 0(sp)
    mv t1, a0
    li t2, 0
    li t3, 0
    slt s2, t3, t1
    sltu t3, t2, s2
    beqz t3, .Lfoo_0
    li t3, 10
    slt s2, t1, t3
    sltu t3, t2, s2
    mv s2, t3
    j .Lfoo_1
.Lfoo_0:
    mv s2, t2
.Lfoo_1:
    mv a0, s2
    ld s2, 0(sp)
    li t0, 16
    add sp, sp, t0
    ret
.size foo, .-foo
