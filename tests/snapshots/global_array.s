.text
.globl sum
.type sum, @function
sum:
    li t0, -16
    add sp, sp, t0
    sd s2, 0(sp)
    mv t1, a0
    lw t2, 0(t1)
    li t3, 4
    add s2, t1, t3
    lw t3, 0(s2)
    addw s2, t2, t3
    li t3, 8
    add t2, t1, t3
    lw t3, 0(t2)
    addw t2, s2, t3
    mv a0, t2
    ld s2, 0(sp)
    li t0, 16
    add sp, sp, t0
    ret
.size sum, .-sum
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
    la t2, y
    sw t1, 0(t2)
    li t3, 4
    add s2, t2, t3
    li t3, 1
    sllw s3, t1, t3
    sw s3, 0(s2)
    li t3, 8
    add s2, t2, t3
    li t3, 3
    addw t1, s3, t3
    sw t1, 0(s2)
    mv a0, t2
    call sum
    mv t2, a0
    mv s2, t2
    mv a0, s2
    ld ra, 16(sp)
    ld s2, 0(sp)
    ld s3, 8(sp)
    li t0, 32
    add sp, sp, t0
    ret
.size foo, .-foo
.bss
.globl y
.type y, @object
.align 2
y:
    .zero 12
.size y, 12
