.text
.globl gety
.type gety, @function
gety:
    mv t1, a0
    li t2, 4
    add t3, t1, t2
    lw t2, 0(t3)
    mv a0, t2
    ret
.size gety, .-gety
.text
.globl setx
.type setx, @function
setx:
    mv t1, a0
    mv t2, a1
    sw t2, 0(t1)
    ret
.size setx, .-setx
.text
.globl foo
.type foo, @function
foo:
    li t0, -32
    add sp, sp, t0
    sd s2, 0(sp)
    sd ra, 8(sp)
    li t0, 16
    add s2, sp, t0
    li t1, 1
    sw t1, 0(s2)
    li t1, 4
    add t2, s2, t1
    li t1, 9
    sw t1, 0(t2)
    li t1, 5
    mv a0, s2
    mv a1, t1
    call setx
    mv t1, a0
    mv a0, s2
    call gety
    mv t1, a0
    mv t2, t1
    lw t1, 0(s2)
    addw s2, t2, t1
    mv a0, s2
    ld ra, 8(sp)
    ld s2, 0(sp)
    li t0, 32
    add sp, sp, t0
    ret
.size foo, .-foo
