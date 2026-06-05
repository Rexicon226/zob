.text
.globl foo
.type foo, @function
foo:
    li t0, -32
    add sp, sp, t0
    sd s2, 0(sp)
    sd s3, 8(sp)
    sd s4, 16(sp)
    li t0, 24
    add t1, sp, t0
    lw t2, 0(t1)
    mv t3, t2
    li t2, -16
    and s2, t3, t2
    li t2, 2
    or t3, s2, t2
    sw t3, 0(t1)
    lw t2, 0(t1)
    mv t3, t2
    li t2, -241
    and s2, t3, t2
    li t2, 128
    or t3, s2, t2
    sw t3, 0(t1)
    lw t2, 0(t1)
    mv t3, t2
    li t2, -65281
    and s2, t3, t2
    li t2, 1536
    or t3, s2, t2
    sw t3, 0(t1)
    lw t2, 0(t1)
    mv t1, t2
    li t2, 60
    sll t3, t1, t2
    srl s2, t3, t2
    sext.w t3, s2
    li s2, 100
    mulw s3, t3, s2
    li s2, 56
    sll t3, t1, s2
    srl s4, t3, t2
    sext.w t3, s4
    li s4, 10
    mulw t2, t3, s4
    addw s4, s3, t2
    li s3, 48
    sll t2, t1, s3
    srl s3, t2, s2
    sext.w s2, s3
    addw s3, s4, s2
    mv a0, s3
    ld s2, 0(sp)
    ld s3, 8(sp)
    ld s4, 16(sp)
    li t0, 32
    add sp, sp, t0
    ret
.size foo, .-foo
