.text
.globl callback
.type callback, @function
callback:
    mv t1, a0
    li t2, 10
    addw t3, t1, t2
    mv a0, t3
    ret
.size callback, .-callback
.text
.globl bar
.type bar, @function
bar:
    li t0, -16
    add sp, sp, t0
    sd ra, 0(sp)
    mv t1, a0
    li t2, 8
    add t3, t1, t2
    ld t2, 0(t3)
    lw t3, 0(t1)
    mv a0, t3
    jalr ra, t2, 0
    mv t3, a0
    mv t2, t3
    mv a0, t2
    ld ra, 0(sp)
    li t0, 16
    add sp, sp, t0
    ret
.size bar, .-bar
.text
.globl foo
.type foo, @function
foo:
    li t0, -32
    add sp, sp, t0
    sd ra, 0(sp)
    li t0, 8
    add t1, sp, t0
    li t2, 42
    sw t2, 0(t1)
    li t2, 8
    add t3, t1, t2
    la t2, callback
    sd t2, 0(t3)
    mv a0, t1
    call bar
    mv t3, a0
    mv t2, t3
    mv a0, t2
    ld ra, 0(sp)
    li t0, 32
    add sp, sp, t0
    ret
.size foo, .-foo
