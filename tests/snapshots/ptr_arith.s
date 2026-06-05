.text
.globl sum3
.type sum3, @function
sum3:
    li t0, -16
    add sp, sp, t0
    sd s2, 0(sp)
    mv t1, a0
    lw t2, 0(t1)
    li t3, 4
    add s2, t1, t3
    lw t3, 0(s2)
    addw s2, t2, t3
    li t3, 8
    add t2, t1, t3
    lw t3, 0(t2)
    addw t2, s2, t3
    mv a0, t2
    ld s2, 0(sp)
    li t0, 16
    add sp, sp, t0
    ret
.size sum3, .-sum3
.text
.globl foo
.type foo, @function
foo:
    li t0, -32
    add sp, sp, t0
    sd ra, 0(sp)
    li t0, 8
    add t1, sp, t0
    li t2, 1
    sw t2, 0(t1)
    li t2, 4
    add t3, t1, t2
    li t2, 2
    sw t2, 0(t3)
    li t2, 8
    add t3, t1, t2
    li t2, 3
    sw t2, 0(t3)
    mv a0, t1
    call sum3
    mv t3, a0
    mv t2, t3
    mv a0, t2
    ld ra, 0(sp)
    li t0, 32
    add sp, sp, t0
    ret
.size foo, .-foo
