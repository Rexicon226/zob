.text
.globl sum
.type sum, @function
sum:
    li t0, -16
    add sp, sp, t0
    sd s2, 0(sp)
    mv t1, a0
    lw t2, 0(t1)
    li t3, 100
    addw s2, t2, t3
    sw s2, 0(t1)
    li t3, 4
    add t2, t1, t3
    lw t3, 0(t2)
    addw t2, s2, t3
    mv a0, t2
    ld s2, 0(sp)
    li t0, 16
    add sp, sp, t0
    ret
.size sum, .-sum
.text
.globl foo
.type foo, @function
foo:
    li t0, -32
    add sp, sp, t0
    sd s2, 0(sp)
    sd ra, 8(sp)
    li t0, 16
    add s2, sp, t0
    li t1, 10
    sw t1, 0(s2)
    li t1, 4
    add t2, s2, t1
    li t1, 20
    sw t1, 0(t2)
    li t0, 24
    add t1, sp, t0
    ld t2, 0(s2)
    sd t2, 0(t1)
    mv a0, t1
    call sum
    mv t2, a0
    mv t1, t2
    lw t2, 0(s2)
    addw s2, t1, t2
    mv a0, s2
    ld ra, 8(sp)
    ld s2, 0(sp)
    li t0, 32
    add sp, sp, t0
    ret
.size foo, .-foo
