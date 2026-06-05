.text
.globl foo
.type foo, @function
foo:
    li t0, -16
    add sp, sp, t0
    sd s2, 0(sp)
    mv t1, a0
    li t2, 1
    xor t3, t1, t2
    seqz t3, t3
    beqz t3, .Lfoo_0
    li t3, 5
    mv t2, t3
    j .Lfoo_1
.Lfoo_0:
    li t3, 2
    xor s2, t1, t3
    seqz s2, s2
    beqz s2, .Lfoo_2
    li t3, 6
    mv s2, t3
    j .Lfoo_3
.Lfoo_2:
    li t3, -1
    mv s2, t3
.Lfoo_3:
    mv t2, s2
.Lfoo_1:
    mv a0, t2
    ld s2, 0(sp)
    li t0, 16
    add sp, sp, t0
    ret
.size foo, .-foo
