.text
.globl foo
.type foo, @function
foo:
    li t0, -16
    add sp, sp, t0
    sd s2, 0(sp)
    li t0, 8
    add t1, sp, t0
    lw t2, 0(t1)
    mv t3, t2
    li t2, -8
    and s2, t3, t2
    li t2, 5
    or t3, s2, t2
    sw t3, 0(t1)
    lw t2, 0(t1)
    mv t3, t2
    li t2, -57
    and s2, t3, t2
    sw s2, 0(t1)
    lw t2, 0(t1)
    mv t1, t2
    li t2, 61
    sll s2, t1, t2
    srl t1, s2, t2
    sext.w t2, t1
    mv a0, t2
    ld s2, 0(sp)
    li t0, 16
    add sp, sp, t0
    ret
.size foo, .-foo
