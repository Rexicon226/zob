.text
.globl foo
.type foo, @function
foo:
    li t0, -64
    add sp, sp, t0
    sd s2, 0(sp)
    sd s3, 8(sp)
    sd s4, 16(sp)
    li t0, 24
    add t1, sp, t0
    li t2, 5
    sw t2, 0(t1)
    li t2, 4
    add t3, t1, t2
    add s2, t3, t2
    li t3, 20
    sw t3, 0(s2)
    li t0, 40
    add t3, sp, t0
    ld s2, 0(t1)
    sd s2, 0(t3)
    li s2, 8
    add s3, t3, s2
    add s4, t1, s2
    ld s2, 0(s4)
    sd s2, 0(s3)
    li s3, 9
    sw s3, 0(t3)
    add s3, t3, t2
    add t3, s3, t2
    lw t2, 0(t3)
    li t3, 14
    addw s3, t2, t3
    mv a0, s3
    ld s2, 0(sp)
    ld s3, 8(sp)
    ld s4, 16(sp)
    li t0, 64
    add sp, sp, t0
    ret
.size foo, .-foo
