.text
.globl add
.type add, @function
add:
    mv t0, a0
    mv t1, a1
    lw t2, 0(t0)
    addw t3, t1, t2
    sw t3, 0(t0)
    ret
.size add, .-add
.text
.globl foo
.type foo, @function
foo:
    addi sp, sp, -32
    sd s2, 0(sp)
    sd s3, 8(sp)
    sd ra, 16(sp)
    mv t0, a0
    addi s2, sp, 24
    sw t0, 0(s2)
    addi s3, sp, 28
    li t1, 0
    sw t1, 0(s3)
    mv a0, s3
    mv a1, t0
    call add
    mv t1, a0
    li t1, 25
    mv a0, s3
    mv a1, t1
    call add
    mv t1, a0
    li t1, 100
    mv a0, s2
    mv a1, t1
    call add
    mv t1, a0
    lw t1, 0(s3)
    mv a0, t1
    ld ra, 16(sp)
    ld s2, 0(sp)
    ld s3, 8(sp)
    addi sp, sp, 32
    ret
.size foo, .-foo
