.text
.globl foo
.type foo, @function
foo:
    li t0, -16
    add sp, sp, t0
    sd s2, 0(sp)
    mv t1, a0
    mv t2, a1
    li t3, 10
    mulw s2, t1, t3
    addw t3, s2, t2
    mv a0, t3
    ld s2, 0(sp)
    li t0, 16
    add sp, sp, t0
    ret
.size foo, .-foo
