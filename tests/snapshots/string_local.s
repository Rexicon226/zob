.text
.globl foo
.type foo, @function
foo:
    addi sp, sp, -16
    sd s2, 0(sp)
    mv t0, a0
    addi t1, sp, 8
    li t2, 104
    sb t2, 0(t1)
    li t2, 1
    add t3, t1, t2
    li t2, 105
    sb t2, 0(t3)
    li t2, 2
    add t3, t1, t2
    li t2, 0
    sb t2, 0(t3)
    li t3, 3
    add s2, t1, t3
    sb t2, 0(s2)
    li s2, 4
    add t3, t1, s2
    sb t2, 0(t3)
    li t3, 5
    add s2, t1, t3
    sb t2, 0(s2)
    li s2, 6
    add t3, t1, s2
    sb t2, 0(t3)
    li t3, 7
    add s2, t1, t3
    sb t2, 0(s2)
    mv t3, t0
    add t0, t1, t3
    lb t1, 0(t0)
    andi t0, t1, 255
    mv a0, t0
    ld s2, 0(sp)
    addi sp, sp, 16
    ret
.size foo, .-foo
