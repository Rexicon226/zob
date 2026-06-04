.text
.globl dbl
.type dbl, @function
dbl:
    addi sp, sp, -16
    sd s2, 0(sp)
    sd s3, 8(sp)
    mv t0, a0
    mv t1, a1
    lw t2, 0(t0)
    li t3, 1
    sllw s2, t2, t3
    sw s2, 0(t0)
    li s2, 4
    add t2, t0, s2
    lw s2, 0(t2)
    sllw s3, s2, t3
    sw s3, 0(t2)
    ld t2, 0(t0)
    sd t2, 0(t1)
    ld s2, 0(sp)
    ld s3, 8(sp)
    addi sp, sp, 16
    ret
.size dbl, .-dbl
.text
.globl foo
.type foo, @function
foo:
    addi sp, sp, -64
    sd s2, 0(sp)
    sd s3, 8(sp)
    sd s4, 16(sp)
    sd ra, 24(sp)
    addi s2, sp, 32
    li t0, 3
    sw t0, 0(s2)
    li s3, 4
    add t0, s2, s3
    li t1, 4
    sw t1, 0(t0)
    addi t1, sp, 40
    ld t0, 0(s2)
    sd t0, 0(t1)
    addi s4, sp, 48
    mv a0, t1
    mv a1, s4
    call dbl
    mv t1, a0
    addi t1, sp, 56
    ld t0, 0(s4)
    sd t0, 0(t1)
    lw t0, 0(t1)
    li s4, 100
    mulw t2, t0, s4
    add s4, t1, s3
    lw t1, 0(s4)
    li s4, 10
    mulw s3, t1, s4
    addw s4, t2, s3
    lw t2, 0(s2)
    addw s2, s4, t2
    mv a0, s2
    ld ra, 24(sp)
    ld s2, 0(sp)
    ld s3, 8(sp)
    ld s4, 16(sp)
    addi sp, sp, 64
    ret
.size foo, .-foo
