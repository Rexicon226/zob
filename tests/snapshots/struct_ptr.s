.text
.globl gety
.type gety, @function
gety:
    mv t0, a0
    li t1, 4
    add t2, t0, t1
    lw t1, 0(t2)
    mv a0, t1
    ret
.size gety, .-gety
.text
.globl setx
.type setx, @function
setx:
    mv t0, a0
    mv t1, a1
    sw t1, 0(t0)
    ret
.size setx, .-setx
.text
.globl foo
.type foo, @function
foo:
    addi sp, sp, -32
    sd s2, 0(sp)
    sd ra, 8(sp)
    addi s2, sp, 16
    li t0, 1
    sw t0, 0(s2)
    li t0, 4
    add t1, s2, t0
    li t0, 9
    sw t0, 0(t1)
    li t0, 5
    mv a0, s2
    mv a1, t0
    call setx
    mv t0, a0
    mv a0, s2
    call gety
    mv t0, a0
    mv t1, t0
    lw t0, 0(s2)
    addw s2, t1, t0
    mv a0, s2
    ld ra, 8(sp)
    ld s2, 0(sp)
    addi sp, sp, 32
    ret
.size foo, .-foo
