.text
.globl dbl
.type dbl, @function
dbl:
    li t0, -32
    add sp, sp, t0
    sd s2, 0(sp)
    sd s3, 8(sp)
    sd s4, 16(sp)
    mv t1, a0
    mv t2, a1
    lw t3, 0(t1)
    li s2, 1
    sllw s3, t3, s2
    sw s3, 0(t1)
    li s3, 4
    add t3, t1, s3
    lw s3, 0(t3)
    sllw s4, s3, s2
    sw s4, 0(t3)
    ld t3, 0(t1)
    sd t3, 0(t2)
    ld s2, 0(sp)
    ld s3, 8(sp)
    ld s4, 16(sp)
    li t0, 32
    add sp, sp, t0
    ret
.size dbl, .-dbl
.text
.globl foo
.type foo, @function
foo:
    li t0, -64
    add sp, sp, t0
    sd s2, 0(sp)
    sd s3, 8(sp)
    sd s4, 16(sp)
    sd ra, 24(sp)
    li t0, 32
    add s2, sp, t0
    li t1, 3
    sw t1, 0(s2)
    li s3, 4
    add t1, s2, s3
    li t2, 4
    sw t2, 0(t1)
    li t0, 40
    add t2, sp, t0
    ld t1, 0(s2)
    sd t1, 0(t2)
    li t0, 48
    add s4, sp, t0
    mv a0, t2
    mv a1, s4
    call dbl
    mv t2, a0
    li t0, 56
    add t2, sp, t0
    ld t1, 0(s4)
    sd t1, 0(t2)
    lw t1, 0(t2)
    li s4, 100
    mulw t3, t1, s4
    add s4, t2, s3
    lw t2, 0(s4)
    li s4, 10
    mulw s3, t2, s4
    addw s4, t3, s3
    lw t3, 0(s2)
    addw s2, s4, t3
    mv a0, s2
    ld ra, 24(sp)
    ld s2, 0(sp)
    ld s3, 8(sp)
    ld s4, 16(sp)
    li t0, 64
    add sp, sp, t0
    ret
.size foo, .-foo
