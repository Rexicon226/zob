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
    li t2, 1
    sw t2, 0(t1)
    li t2, 4
    add t3, t1, t2
    li s2, 2
    sw s2, 0(t3)
    li t0, 24
    add s2, sp, t0
    li t3, 0
    sw t3, 0(s2)
    add s3, s2, t2
    sw t3, 0(s3)
    ld t3, 0(t1)
    sd t3, 0(s2)
    lw t3, 0(s2)
    li s2, 10
    mulw t1, t3, s2
    lw s2, 0(s3)
    addw s3, t1, s2
    mv a0, s3
    ld s2, 0(sp)
    ld s3, 8(sp)
    li t0, 32
    add sp, sp, t0
    ret
.size foo, .-foo
