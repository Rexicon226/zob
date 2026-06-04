.text
.globl pick
.type pick, @function
pick:
    addi sp, sp, -16
    sd s2, 0(sp)
    mv t0, a0
    mv t1, a1
    li t2, 0
    sltu t3, t2, t0
    addi t2, sp, 8
    li t0, 4
    add s2, t2, t0
    beqz t3, .Lpick_0
    li t0, 9
    sw t0, 0(t2)
    sw t0, 0(s2)
    j .Lpick_1
.Lpick_0:
    li t0, 1
    sw t0, 0(t2)
    li t0, 2
    sw t0, 0(s2)
.Lpick_1:
    ld t0, 0(t2)
    sd t0, 0(t1)
    ld s2, 0(sp)
    addi sp, sp, 16
    ret
.size pick, .-pick
.text
.globl foo
.type foo, @function
foo:
    addi sp, sp, -32
    sd s2, 0(sp)
    sd ra, 8(sp)
    mv t0, a0
    addi s2, sp, 16
    mv a0, t0
    mv a1, s2
    call pick
    mv t0, a0
    addi t0, sp, 24
    ld t1, 0(s2)
    sd t1, 0(t0)
    lw t1, 0(t0)
    li s2, 10
    mulw t2, t1, s2
    li s2, 4
    add t1, t0, s2
    lw s2, 0(t1)
    addw t1, t2, s2
    mv a0, t1
    ld ra, 8(sp)
    ld s2, 0(sp)
    addi sp, sp, 32
    ret
.size foo, .-foo
