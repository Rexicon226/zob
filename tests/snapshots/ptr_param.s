.text
.globl set
.type set, @function
set:
    mv t0, a0
    mv t1, a1
    sw t1, 0(t0)
    ret
.size set, .-set
.text
.globl foo
.type foo, @function
foo:
    addi sp, sp, -32
    sd s2, 0(sp)
    sd ra, 8(sp)
    addi t0, sp, 16
    li t1, 4
    add s2, t0, t1
    li t1, 42
    mv a0, s2
    mv a1, t1
    call set
    mv t1, a0
    lw t1, 0(s2)
    mv a0, t1
    ld ra, 8(sp)
    ld s2, 0(sp)
    addi sp, sp, 32
    ret
.size foo, .-foo
