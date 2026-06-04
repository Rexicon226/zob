.text
.globl foo
.type foo, @function
foo:
    addi sp, sp, -32
    sd s2, 0(sp)
    addi t0, sp, 8
    li t1, 7
    sw t1, 0(t0)
    li t1, 4
    add t2, t0, t1
    li t3, 8
    sw t3, 0(t2)
    addi t3, sp, 16
    ld t2, 0(t0)
    sd t2, 0(t3)
    lw t2, 0(t3)
    li t0, 10
    mulw s2, t2, t0
    add t0, t3, t1
    lw t1, 0(t0)
    addw t0, s2, t1
    li s2, 5
    addw t1, t0, s2
    li s2, 4
    subw t0, t1, s2
    mv a0, t0
    ld s2, 0(sp)
    addi sp, sp, 32
    ret
.size foo, .-foo
