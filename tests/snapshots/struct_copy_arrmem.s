.text
.globl foo
.type foo, @function
foo:
    addi sp, sp, -48
    sd s2, 0(sp)
    sd s3, 8(sp)
    addi t0, sp, 16
    li t1, 5
    sw t1, 0(t0)
    li t1, 4
    add t2, t0, t1
    add t3, t2, t1
    li t2, 20
    sw t2, 0(t3)
    addi t2, sp, 32
    ld t3, 0(t0)
    sd t3, 0(t2)
    li t3, 8
    add s2, t2, t3
    add s3, t0, t3
    ld t3, 0(s3)
    sd t3, 0(s2)
    li s2, 9
    sw s2, 0(t2)
    add s2, t2, t1
    add t2, s2, t1
    lw t1, 0(t2)
    li t2, 14
    addw s2, t1, t2
    mv a0, s2
    ld s2, 0(sp)
    ld s3, 8(sp)
    addi sp, sp, 48
    ret
.size foo, .-foo
