.text
.globl foo
.type foo, @function
foo:
    li t0, -16
    add sp, sp, t0
    sd s2, 0(sp)
    mv t1, a0
    mv t2, a1
    li t3, 0
    sltu s2, t3, t1
    beqz s2, .Lfoo_0
    sltu s2, t3, t2
    mv t2, s2
    j .Lfoo_1
.Lfoo_0:
    mv t2, t3
.Lfoo_1:
    mv a0, t2
    ld s2, 0(sp)
    li t0, 16
    add sp, sp, t0
    ret
.size foo, .-foo
