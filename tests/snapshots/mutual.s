.text
.globl is_even
.type is_even, @function
is_even:
    li t0, -32
    add sp, sp, t0
    sd s2, 0(sp)
    sd s3, 8(sp)
    sd ra, 16(sp)
    mv t1, a0
    li t2, 0
    li t3, 0
    xor s2, t1, t3
    seqz s2, s2
    sltu t3, t2, s2
    li s2, 1
    beqz t3, .Lis_even_0
    mv s3, s2
    j .Lis_even_1
.Lis_even_0:
    subw t3, t1, s2
    mv a0, t3
    call is_odd
    mv s2, a0
    mv t3, s2
    mv s3, t3
.Lis_even_1:
    mv a0, s3
    ld ra, 16(sp)
    ld s2, 0(sp)
    ld s3, 8(sp)
    li t0, 32
    add sp, sp, t0
    ret
.size is_even, .-is_even
.text
.globl is_odd
.type is_odd, @function
is_odd:
    li t0, -32
    add sp, sp, t0
    sd s2, 0(sp)
    sd s3, 8(sp)
    sd ra, 16(sp)
    mv t1, a0
    li t2, 0
    li t3, 0
    xor s2, t1, t3
    seqz s2, s2
    sltu s3, t2, s2
    beqz s3, .Lis_odd_0
    mv s2, t3
    j .Lis_odd_1
.Lis_odd_0:
    li t3, 1
    subw s3, t1, t3
    mv a0, s3
    call is_even
    mv t3, a0
    mv s3, t3
    mv s2, s3
.Lis_odd_1:
    mv a0, s2
    ld ra, 16(sp)
    ld s2, 0(sp)
    ld s3, 8(sp)
    li t0, 32
    add sp, sp, t0
    ret
.size is_odd, .-is_odd
.text
.globl foo
.type foo, @function
foo:
    li t0, -16
    add sp, sp, t0
    sd ra, 0(sp)
    mv t1, a0
    mv a0, t1
    call is_even
    mv t1, a0
    mv t2, t1
    mv a0, t2
    ld ra, 0(sp)
    li t0, 16
    add sp, sp, t0
    ret
.size foo, .-foo
