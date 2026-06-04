.text
.globl foo
.type foo, @function
foo:
    addi sp, sp, -16
    sd s2, 0(sp)
    addi t0, sp, 8
    lw t1, 0(t0)
    mv t2, t1
    li t1, -8
    and t3, t2, t1
    li t1, 5
    or t2, t3, t1
    sw t2, 0(t0)
    lw t1, 0(t0)
    mv t2, t1
    li t1, -249
    and t3, t2, t1
    li t1, 160
    or t2, t3, t1
    sw t2, 0(t0)
    lw t1, 0(t0)
    mv t2, t1
    li t1, -3841
    and t3, t2, t1
    li t1, 3328
    or t2, t3, t1
    sw t2, 0(t0)
    lw t1, 0(t0)
    mv t0, t1
    li t1, 61
    sll t2, t0, t1
    srl t3, t2, t1
    sext.w t2, t3
    li t3, 100
    mulw t1, t2, t3
    li t3, 56
    sll t2, t0, t3
    li t3, 59
    srl s2, t2, t3
    sext.w t3, s2
    addw s2, t1, t3
    li t3, 52
    sll t1, t0, t3
    li t3, 60
    sra t0, t1, t3
    sext.w t3, t0
    li t0, 10
    addw t1, t3, t0
    addw t0, s2, t1
    mv a0, t0
    ld s2, 0(sp)
    addi sp, sp, 16
    ret
.size foo, .-foo
