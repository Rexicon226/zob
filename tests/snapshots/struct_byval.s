.text
.globl sum
.type sum, @function
sum:
    mv t0, a0
    lw t1, 0(t0)
    li t2, 100
    addw t3, t1, t2
    sw t3, 0(t0)
    li t2, 4
    add t1, t0, t2
    lw t2, 0(t1)
    addw t1, t3, t2
    mv a0, t1
    ret
.size sum, .-sum
.text
.globl foo
.type foo, @function
foo:
    addi sp, sp, -32
    sd s2, 0(sp)
    sd ra, 8(sp)
    addi s2, sp, 16
    li t0, 10
    sw t0, 0(s2)
    li t0, 4
    add t1, s2, t0
    li t0, 20
    sw t0, 0(t1)
    addi t0, sp, 24
    ld t1, 0(s2)
    sd t1, 0(t0)
    mv a0, t0
    call sum
    mv t1, a0
    mv t0, t1
    lw t1, 0(s2)
    addw s2, t0, t1
    mv a0, s2
    ld ra, 8(sp)
    ld s2, 0(sp)
    addi sp, sp, 32
    ret
.size foo, .-foo
