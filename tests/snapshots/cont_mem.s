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
    li t3, 1
    sw t3, 0(t2)
    j .Lfoo_1
.Lfoo_0:
    li t3, 2
    sw t3, 0(t2)
.Lfoo_1:
    lw t3, 0(t2)
    mv a0, t3
    ld s2, 0(sp)
    li t0, 16
    add sp, sp, t0
    ret
.size foo, .-foo
