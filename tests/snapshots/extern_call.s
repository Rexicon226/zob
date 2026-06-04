.text
.globl foo
.type foo, @function
foo:
    addi sp, sp, -16
    sd ra, 0(sp)
    mv t0, a0
    mv a0, t0
    call strlen
    mv t0, a0
    mv t1, t0
    sext.w t0, t1
    mv a0, t0
    ld ra, 0(sp)
    addi sp, sp, 16
    ret
.size foo, .-foo
