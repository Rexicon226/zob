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
    li t2, 7
    sw t2, 0(t1)
    li t2, 4
    add t3, t1, t2
    li s2, 8
    sw s2, 0(t3)
    li t0, 24
    add s2, sp, t0
    ld t3, 0(t1)
    sd t3, 0(s2)
    lw t3, 0(s2)
    li t1, 10
    mulw s3, t3, t1
    add t1, s2, t2
    lw t2, 0(t1)
    addw t1, s3, t2
    li s3, 5
    addw t2, t1, s3
    li s3, 4
    subw t1, t2, s3
    mv a0, t1
    ld s2, 0(sp)
    ld s3, 8(sp)
    li t0, 32
    add sp, sp, t0
    ret
.size foo, .-foo
