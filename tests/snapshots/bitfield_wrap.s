.text
.globl foo
.type foo, @function
foo:
    addi sp, sp, -16
    addi t0, sp, 0
    lw t1, 0(t0)
    mv t2, t1
    li t1, -8
    and t3, t2, t1
    li t1, 5
    or t2, t3, t1
    sw t2, 0(t0)
    lw t1, 0(t0)
    mv t2, t1
    li t1, -57
    and t3, t2, t1
    sw t3, 0(t0)
    lw t1, 0(t0)
    mv t0, t1
    li t1, 61
    sll t3, t0, t1
    srl t0, t3, t1
    sext.w t1, t0
    mv a0, t1
    addi sp, sp, 16
    ret
.size foo, .-foo
