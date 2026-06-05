.text
.globl add
.type add, @function
add:
    li t0, -16
    add sp, sp, t0
    sd s2, 0(sp)
    mv t1, a0
    mv t2, a1
    lw t3, 0(t1)
    addw s2, t2, t3
    sw s2, 0(t1)
    ld s2, 0(sp)
    li t0, 16
    add sp, sp, t0
    ret
.size add, .-add
.text
.globl foo
.type foo, @function
foo:
    li t0, -32
    add sp, sp, t0
    sd s2, 0(sp)
    sd s3, 8(sp)
    sd ra, 16(sp)
    mv t1, a0
    li t0, 24
    add s2, sp, t0
    sw t1, 0(s2)
    li t0, 28
    add s3, sp, t0
    li t2, 0
    sw t2, 0(s3)
    mv a0, s3
    mv a1, t1
    call add
    mv t2, a0
    li t2, 25
    mv a0, s3
    mv a1, t2
    call add
    mv t2, a0
    li t2, 100
    mv a0, s2
    mv a1, t2
    call add
    mv t2, a0
    lw t2, 0(s3)
    mv a0, t2
    ld ra, 16(sp)
    ld s2, 0(sp)
    ld s3, 8(sp)
    li t0, 32
    add sp, sp, t0
    ret
.size foo, .-foo
