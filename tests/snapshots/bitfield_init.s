.text
.globl foo
.type foo, @function
foo:
    addi sp, sp, -32
    sd s2, 0(sp)
    sd s3, 8(sp)
    addi t0, sp, 16
    lw t1, 0(t0)
    mv t2, t1
    li t1, -16
    and t3, t2, t1
    li t1, 2
    or t2, t3, t1
    sw t2, 0(t0)
    lw t1, 0(t0)
    mv t2, t1
    li t1, -241
    and t3, t2, t1
    li t1, 128
    or t2, t3, t1
    sw t2, 0(t0)
    lw t1, 0(t0)
    mv t2, t1
    li t1, -65281
    and t3, t2, t1
    li t1, 1536
    or t2, t3, t1
    sw t2, 0(t0)
    lw t1, 0(t0)
    mv t0, t1
    li t1, 60
    sll t2, t0, t1
    srl t3, t2, t1
    sext.w t2, t3
    li t3, 100
    mulw s2, t2, t3
    li t3, 56
    sll t2, t0, t3
    srl s3, t2, t1
    sext.w t2, s3
    li s3, 10
    mulw t1, t2, s3
    addw s3, s2, t1
    li s2, 48
    sll t1, t0, s2
    srl s2, t1, t3
    sext.w t3, s2
    addw s2, s3, t3
    mv a0, s2
    ld s2, 0(sp)
    ld s3, 8(sp)
    addi sp, sp, 32
    ret
.size foo, .-foo
