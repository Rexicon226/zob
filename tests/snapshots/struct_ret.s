.text
.globl make
.type make, @function
make:
    addi sp, sp, -16
    sd s2, 0(sp)
    mv t0, a0
    mv t1, a1
    mv t2, a2
    addi t3, sp, 8
    sw t0, 0(t3)
    li t0, 4
    add s2, t3, t0
    sw t1, 0(s2)
    ld t0, 0(t3)
    sd t0, 0(t2)
    ld s2, 0(sp)
    addi sp, sp, 16
    ret
.size make, .-make
.text
.globl foo
.type foo, @function
foo:
    addi sp, sp, -32
    sd s2, 0(sp)
    sd ra, 8(sp)
    li t0, 7
    li t1, 3
    addi s2, sp, 16
    mv a0, t0
    mv a1, t1
    mv a2, s2
    call make
    mv t1, a0
    addi t1, sp, 24
    ld t0, 0(s2)
    sd t0, 0(t1)
    lw t0, 0(t1)
    li s2, 10
    mulw t2, t0, s2
    li s2, 4
    add t0, t1, s2
    lw s2, 0(t0)
    addw t0, t2, s2
    mv a0, t0
    ld ra, 8(sp)
    ld s2, 0(sp)
    addi sp, sp, 32
    ret
.size foo, .-foo
