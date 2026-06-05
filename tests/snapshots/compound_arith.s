.text
.globl foo
.type foo, @function
foo:
    li t0, -16
    add sp, sp, t0
    sd s2, 0(sp)
    mv t1, a0
    li t2, 5
    addw t3, t1, t2
    li t2, 2
    subw t1, t3, t2
    li t3, 3
    mulw s2, t1, t3
    divw t3, s2, t2
    li t2, 17
    remw s2, t3, t2
    mv a0, s2
    ld s2, 0(sp)
    li t0, 16
    add sp, sp, t0
    ret
.size foo, .-foo
