.text
.globl foo
.type foo, @function
foo:
    li t0, -32
    add sp, sp, t0
    sd s2, 0(sp)
    sd s3, 8(sp)
    mv t1, a0
    li t0, 16
    add t2, sp, t0
    li t3, 104
    sb t3, 0(t2)
    li t3, 1
    add s2, t2, t3
    li t3, 105
    sb t3, 0(s2)
    li t3, 2
    add s2, t2, t3
    li t3, 0
    sb t3, 0(s2)
    li s2, 3
    add s3, t2, s2
    sb t3, 0(s3)
    li s3, 4
    add s2, t2, s3
    sb t3, 0(s2)
    li s2, 5
    add s3, t2, s2
    sb t3, 0(s3)
    li s3, 6
    add s2, t2, s3
    sb t3, 0(s2)
    li s2, 7
    add s3, t2, s2
    sb t3, 0(s3)
    mv s2, t1
    add t1, t2, s2
    lb t2, 0(t1)
    andi t1, t2, 255
    mv a0, t1
    ld s2, 0(sp)
    ld s3, 8(sp)
    li t0, 32
    add sp, sp, t0
    ret
.size foo, .-foo
