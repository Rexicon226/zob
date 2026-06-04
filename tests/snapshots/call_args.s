.text
.globl sum4
.type sum4, @function
sum4:
    addi sp, sp, -16
    sd s2, 0(sp)
    mv t0, a3
    mv t1, a2
    mv t2, a0
    mv t3, a1
    addw s2, t2, t3
    addw t3, t1, s2
    addw s2, t0, t3
    mv a0, s2
    ld s2, 0(sp)
    addi sp, sp, 16
    ret
.size sum4, .-sum4
.text
.globl foo
.type foo, @function
foo:
    addi sp, sp, -16
    sd ra, 0(sp)
    mv t0, a0
    li t1, 1
    li t2, 2
    li t3, 3
    mv a0, t0
    mv a1, t1
    mv a2, t2
    mv a3, t3
    call sum4
    mv t1, a0
    mv t2, t1
    mv a0, t2
    ld ra, 0(sp)
    addi sp, sp, 16
    ret
.size foo, .-foo
