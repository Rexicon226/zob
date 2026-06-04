.text
.globl sum
.type sum, @function
sum:
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
.size sum, .-sum
.text
.globl foo
.type foo, @function
foo:
    addi sp, sp, -16
    sd s2, 0(sp)
    sd ra, 8(sp)
    mv t0, a0
    la t1, y
    sw t0, 0(t1)
    li t2, 4
    add t3, t1, t2
    li t2, 1
    sllw s2, t0, t2
    sw s2, 0(t3)
    li t2, 8
    add t3, t1, t2
    li t2, 3
    addw t0, s2, t2
    sw t0, 0(t3)
    mv a0, t1
    call sum
    mv t1, a0
    mv t3, t1
    mv a0, t3
    ld ra, 8(sp)
    ld s2, 0(sp)
    addi sp, sp, 16
    ret
.size foo, .-foo
.bss
.globl y
.type y, @object
.align 2
y:
    .zero 12
.size y, 12
