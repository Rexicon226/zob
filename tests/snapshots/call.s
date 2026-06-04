.text
.globl add
.type add, @function
add:
    mv t0, a0
    mv t1, a1
    addw t2, t0, t1
    mv a0, t2
    ret
.size add, .-add
.text
.globl foo
.type foo, @function
foo:
    addi sp, sp, -16
    sd ra, 0(sp)
    mv t0, a0
    li t1, 10
    mv a0, t0
    mv a1, t1
    call add
    mv t1, a0
    mv t0, t1
    mv a0, t0
    ld ra, 0(sp)
    addi sp, sp, 16
    ret
.size foo, .-foo
