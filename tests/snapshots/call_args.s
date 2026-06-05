.text
.globl sum4
.type sum4, @function
sum4:
    li t0, -16
    add sp, sp, t0
    sd s2, 0(sp)
    sd s3, 8(sp)
    mv t1, a3
    mv t2, a2
    mv t3, a0
    mv s2, a1
    addw s3, t3, s2
    addw s2, t2, s3
    addw s3, t1, s2
    mv a0, s3
    ld s2, 0(sp)
    ld s3, 8(sp)
    li t0, 16
    add sp, sp, t0
    ret
.size sum4, .-sum4
.text
.globl foo
.type foo, @function
foo:
    li t0, -16
    add sp, sp, t0
    sd s2, 0(sp)
    sd ra, 8(sp)
    mv t1, a0
    li t2, 1
    li t3, 2
    li s2, 3
    mv a0, t1
    mv a1, t2
    mv a2, t3
    mv a3, s2
    call sum4
    mv t2, a0
    mv t3, t2
    mv a0, t3
    ld ra, 8(sp)
    ld s2, 0(sp)
    li t0, 16
    add sp, sp, t0
    ret
.size foo, .-foo
