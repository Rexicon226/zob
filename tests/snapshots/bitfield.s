.text
.globl foo
.type foo, @function
foo:
    li t0, -32
    add sp, sp, t0
    sd s2, 0(sp)
    sd s3, 8(sp)
    li t0, 16
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
    li t2, -249
    and s2, t3, t2
    li t2, 160
    or t3, s2, t2
    sw t3, 0(t1)
    lw t2, 0(t1)
    mv t3, t2
    li t2, -3841
    and s2, t3, t2
    li t2, 3328
    or t3, s2, t2
    sw t3, 0(t1)
    lw t2, 0(t1)
    mv t1, t2
    li t2, 61
    sll t3, t1, t2
    srl s2, t3, t2
    sext.w t3, s2
    li s2, 100
    mulw t2, t3, s2
    li s2, 56
    sll t3, t1, s2
    li s2, 59
    srl s3, t3, s2
    sext.w s2, s3
    addw s3, t2, s2
    li s2, 52
    sll t2, t1, s2
    li s2, 60
    sra t1, t2, s2
    sext.w s2, t1
    li t1, 10
    addw t2, s2, t1
    addw t1, s3, t2
    mv a0, t1
    ld s2, 0(sp)
    ld s3, 8(sp)
    li t0, 32
    add sp, sp, t0
    ret
.size foo, .-foo
