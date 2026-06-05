.text
.globl make
.type make, @function
make:
    li t0, -32
    add sp, sp, t0
    sd s2, 0(sp)
    sd s3, 8(sp)
    mv t1, a0
    mv t2, a1
    mv t3, a2
    li t0, 16
    add s2, sp, t0
    sw t1, 0(s2)
    li t1, 4
    add s3, s2, t1
    sw t2, 0(s3)
    ld t1, 0(s2)
    sd t1, 0(t3)
    ld s2, 0(sp)
    ld s3, 8(sp)
    li t0, 32
    add sp, sp, t0
    ret
.size make, .-make
.text
.globl foo
.type foo, @function
foo:
    li t0, -32
    add sp, sp, t0
    sd s2, 0(sp)
    sd ra, 8(sp)
    li t1, 7
    li t2, 3
    li t0, 16
    add s2, sp, t0
    mv a0, t1
    mv a1, t2
    mv a2, s2
    call make
    mv t2, a0
    li t0, 24
    add t2, sp, t0
    ld t1, 0(s2)
    sd t1, 0(t2)
    lw t1, 0(t2)
    li s2, 10
    mulw t3, t1, s2
    li s2, 4
    add t1, t2, s2
    lw s2, 0(t1)
    addw t1, t3, s2
    mv a0, t1
    ld ra, 8(sp)
    ld s2, 0(sp)
    li t0, 32
    add sp, sp, t0
    ret
.size foo, .-foo
