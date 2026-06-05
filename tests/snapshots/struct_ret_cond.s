.text
.globl pick
.type pick, @function
pick:
    li t0, -32
    add sp, sp, t0
    sd s2, 0(sp)
    sd s3, 8(sp)
    mv t1, a0
    mv t2, a1
    li t3, 0
    sltu s2, t3, t1
    li t0, 16
    add t3, sp, t0
    li t1, 4
    add s3, t3, t1
    beqz s2, .Lpick_0
    li t1, 9
    sw t1, 0(t3)
    sw t1, 0(s3)
    j .Lpick_1
.Lpick_0:
    li t1, 1
    sw t1, 0(t3)
    li t1, 2
    sw t1, 0(s3)
.Lpick_1:
    ld t1, 0(t3)
    sd t1, 0(t2)
    ld s2, 0(sp)
    ld s3, 8(sp)
    li t0, 32
    add sp, sp, t0
    ret
.size pick, .-pick
.text
.globl foo
.type foo, @function
foo:
    li t0, -32
    add sp, sp, t0
    sd s2, 0(sp)
    sd ra, 8(sp)
    mv t1, a0
    li t0, 16
    add s2, sp, t0
    mv a0, t1
    mv a1, s2
    call pick
    mv t1, a0
    li t0, 24
    add t1, sp, t0
    ld t2, 0(s2)
    sd t2, 0(t1)
    lw t2, 0(t1)
    li s2, 10
    mulw t3, t2, s2
    li s2, 4
    add t2, t1, s2
    lw s2, 0(t2)
    addw t2, t3, s2
    mv a0, t2
    ld ra, 8(sp)
    ld s2, 0(sp)
    li t0, 32
    add sp, sp, t0
    ret
.size foo, .-foo
