.text
.globl __bswap_16
.type __bswap_16, @function
__bswap_16:
    addi sp, sp, -16
    sd s2, 0(sp)
    mv t0, a0
    li t1, 255
    and t2, t0, t1
    li t1, 8
    sll t3, t2, t1
    li t2, 65280
    and s2, t0, t2
    srl t2, s2, t1
    or t1, t3, t2
    mv a0, t1
    ld s2, 0(sp)
    addi sp, sp, 16
    ret
.size __bswap_16, .-__bswap_16
.text
.globl __bswap_32
.type __bswap_32, @function
__bswap_32:
    addi sp, sp, -16
    sd s2, 0(sp)
    sd s3, 8(sp)
    mv t0, a0
    li t1, 255
    and t2, t0, t1
    li t1, 24
    sllw t3, t2, t1
    li t2, 65280
    and s2, t0, t2
    li t2, 8
    sllw s3, s2, t2
    or s2, t3, s3
    li s3, 16711680
    and t3, t0, s3
    srlw s3, t3, t2
    li t3, 4278190080
    and t2, t0, t3
    srlw t3, t2, t1
    or t1, s3, t3
    or s3, s2, t1
    mv a0, s3
    ld s2, 0(sp)
    ld s3, 8(sp)
    addi sp, sp, 16
    ret
.size __bswap_32, .-__bswap_32
.text
.globl __bswap_64
.type __bswap_64, @function
__bswap_64:
    addi sp, sp, -48
    sd s2, 0(sp)
    sd s3, 8(sp)
    sd s4, 16(sp)
    sd s5, 24(sp)
    sd s6, 32(sp)
    mv t0, a0
    li t1, 255
    and t2, t0, t1
    li t1, 56
    sll t3, t2, t1
    li t2, 65280
    and s2, t0, t2
    li t2, 40
    sll s3, s2, t2
    or s2, t3, s3
    li s3, 16711680
    and t3, t0, s3
    li s3, 24
    sll s4, t3, s3
    li t3, 4278190080
    and s5, t0, t3
    li t3, 8
    sll s6, s5, t3
    or s5, s4, s6
    or s6, s2, s5
    li s5, 1095216660480
    and s2, t0, s5
    srl s5, s2, t3
    li s2, 280375465082880
    and t3, t0, s2
    srl s2, t3, s3
    or t3, s5, s2
    li s2, 71776119061217280
    and s5, t0, s2
    srl s2, s5, t2
    li s5, -72057594037927936
    and t2, t0, s5
    srl s5, t2, t1
    or t1, s2, s5
    or s2, t3, t1
    or t3, s6, s2
    mv a0, t3
    ld s2, 0(sp)
    ld s3, 8(sp)
    ld s4, 16(sp)
    ld s5, 24(sp)
    ld s6, 32(sp)
    addi sp, sp, 48
    ret
.size __bswap_64, .-__bswap_64
.text
.globl __uint16_identity
.type __uint16_identity, @function
__uint16_identity:
    mv t0, a0
    mv a0, t0
    ret
.size __uint16_identity, .-__uint16_identity
.text
.globl __uint32_identity
.type __uint32_identity, @function
__uint32_identity:
    mv t0, a0
    mv a0, t0
    ret
.size __uint32_identity, .-__uint32_identity
.text
.globl __uint64_identity
.type __uint64_identity, @function
__uint64_identity:
    mv t0, a0
    mv a0, t0
    ret
.size __uint64_identity, .-__uint64_identity
.text
.globl foo
.type foo, @function
foo:
    addi sp, sp, -48
    sd s2, 0(sp)
    sd s3, 8(sp)
    sd s4, 16(sp)
    sd s5, 24(sp)
    sd ra, 32(sp)
    mv s2, a0
    mv s3, a1
    li t0, 0
    xor t1, s2, t0
    seqz t1, t1
    beqz t1, .Lfoo_0
    slli t1, s3, 48
    srai t1, t1, 48
    mv a0, t1
    call __bswap_16
    mv t1, a0
    mv t0, t1
    slli t1, t0, 48
    srli t1, t1, 48
    mv s4, t1
    j .Lfoo_1
.Lfoo_0:
    li t1, 1
    xor t0, s2, t1
    seqz t0, t0
    beqz t0, .Lfoo_2
    sext.w t0, s3
    mv a0, t0
    call __bswap_32
    mv t0, a0
    mv t1, t0
    slli t0, t1, 32
    srli t0, t0, 32
    mv s5, t0
    j .Lfoo_3
.Lfoo_2:
    li t0, 2
    xor t1, s2, t0
    seqz t1, t1
    beqz t1, .Lfoo_4
    mv a0, s3
    call __bswap_64
    mv s3, a0
    mv t0, s3
    mv s3, t0
    j .Lfoo_5
.Lfoo_4:
    li t0, 0
    mv s3, t0
.Lfoo_5:
    mv s5, s3
.Lfoo_3:
    mv s4, s5
.Lfoo_1:
    mv a0, s4
    ld ra, 32(sp)
    ld s2, 0(sp)
    ld s3, 8(sp)
    ld s4, 16(sp)
    ld s5, 24(sp)
    addi sp, sp, 48
    ret
.size foo, .-foo
