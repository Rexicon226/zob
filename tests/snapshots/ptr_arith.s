.text
.globl sum3
.type sum3, @function
sum3:
    mv t0, a0
    lw t1, 0(t0)
    li t2, 4
    add t3, t0, t2
    lw t2, 0(t3)
    addw t3, t1, t2
    li t2, 8
    add t1, t0, t2
    lw t2, 0(t1)
    addw t1, t3, t2
    mv a0, t1
    ret
.size sum3, .-sum3
.text
.globl foo
.type foo, @function
foo:
    addi sp, sp, -32
    sd ra, 0(sp)
    addi t0, sp, 8
    li t1, 1
    sw t1, 0(t0)
    li t1, 4
    add t2, t0, t1
    li t1, 2
    sw t1, 0(t2)
    li t1, 8
    add t2, t0, t1
    li t1, 3
    sw t1, 0(t2)
    mv a0, t0
    call sum3
    mv t2, a0
    mv t1, t2
    mv a0, t1
    ld ra, 0(sp)
    addi sp, sp, 32
    ret
.size foo, .-foo
