.text
.globl foo
.type foo, @function
foo:
    addi sp, sp, -32
    sd s2, 0(sp)
    addi t0, sp, 8
    li t1, 1
    sw t1, 0(t0)
    li t1, 4
    add t2, t0, t1
    li t3, 2
    sw t3, 0(t2)
    addi t3, sp, 16
    li t2, 0
    sw t2, 0(t3)
    add s2, t3, t1
    sw t2, 0(s2)
    ld t2, 0(t0)
    sd t2, 0(t3)
    lw t2, 0(t3)
    li t3, 10
    mulw t0, t2, t3
    lw t3, 0(s2)
    addw s2, t0, t3
    mv a0, s2
    ld s2, 0(sp)
    addi sp, sp, 32
    ret
.size foo, .-foo
