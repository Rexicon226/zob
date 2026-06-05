.text
.globl foo
.type foo, @function
foo:
    li t0, -16
    add sp, sp, t0
    sd ra, 0(sp)
    mv t1, a0
    mv a0, t1
    call strlen
    mv t1, a0
    mv t2, t1
    sext.w t1, t2
    mv a0, t1
    ld ra, 0(sp)
    li t0, 16
    add sp, sp, t0
    ret
.size foo, .-foo
