.text
.globl set
.type set, @function
set:
    mv t1, a0
    mv t2, a1
    sw t2, 0(t1)
    ret
.size set, .-set
.text
.globl foo
.type foo, @function
foo:
    li t0, -32
    add sp, sp, t0
    sd s2, 0(sp)
    sd ra, 8(sp)
    li t0, 16
    add t1, sp, t0
    li t2, 4
    add s2, t1, t2
    li t2, 42
    mv a0, s2
    mv a1, t2
    call set
    mv t2, a0
    lw t2, 0(s2)
    mv a0, t2
    ld ra, 8(sp)
    ld s2, 0(sp)
    li t0, 32
    add sp, sp, t0
    ret
.size foo, .-foo
