.text
.globl is_even
.type is_even, @function
is_even:
    addi sp, sp, -16
    sd s2, 0(sp)
    sd ra, 8(sp)
    mv t0, a0
    li t1, 0
    li t2, 0
    xor t3, t0, t2
    seqz t3, t3
    sltu t2, t1, t3
    li t3, 1
    beqz t2, .Lis_even_0
    mv s2, t3
    j .Lis_even_1
.Lis_even_0:
    subw t2, t0, t3
    mv a0, t2
    call is_odd
    mv t3, a0
    mv t2, t3
    mv s2, t2
.Lis_even_1:
    mv a0, s2
    ld ra, 8(sp)
    ld s2, 0(sp)
    addi sp, sp, 16
    ret
.size is_even, .-is_even
.text
.globl is_odd
.type is_odd, @function
is_odd:
    addi sp, sp, -16
    sd s2, 0(sp)
    sd ra, 8(sp)
    mv t0, a0
    li t1, 0
    li t2, 0
    xor t3, t0, t2
    seqz t3, t3
    sltu s2, t1, t3
    beqz s2, .Lis_odd_0
    mv s2, t2
    j .Lis_odd_1
.Lis_odd_0:
    li t2, 1
    subw t3, t0, t2
    mv a0, t3
    call is_even
    mv t2, a0
    mv t3, t2
    mv s2, t3
.Lis_odd_1:
    mv a0, s2
    ld ra, 8(sp)
    ld s2, 0(sp)
    addi sp, sp, 16
    ret
.size is_odd, .-is_odd
.text
.globl foo
.type foo, @function
foo:
    addi sp, sp, -16
    sd ra, 0(sp)
    mv t0, a0
    mv a0, t0
    call is_even
    mv t0, a0
    mv t1, t0
    mv a0, t1
    ld ra, 0(sp)
    addi sp, sp, 16
    ret
.size foo, .-foo
