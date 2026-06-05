.text
.globl add
.type add, @function
add:
    mv t1, a0
    mv t2, a1
    addw t3, t1, t2
    mv a0, t3
    ret
.size add, .-add
.text
.globl foo
.type foo, @function
foo:
    li t0, -16
    add sp, sp, t0
    sd ra, 0(sp)
    mv t1, a0
    li t2, 10
    mv a0, t1
    mv a1, t2
    call add
    mv t2, a0
    mv t1, t2
    mv a0, t1
    ld ra, 0(sp)
    li t0, 16
    add sp, sp, t0
    ret
.size foo, .-foo
