.text
.globl __bswap_16
.type __bswap_16, @function
__bswap_16:
    li t0, -16
    add sp, sp, t0
    sd s2, 0(sp)
    sd s3, 8(sp)
    mv t1, a0
    li t2, 255
    and t3, t1, t2
    li t2, 8
    sll s2, t3, t2
    li t3, 65280
    and s3, t1, t3
    srl t3, s3, t2
    or t2, s2, t3
    mv a0, t2
    ld s2, 0(sp)
    ld s3, 8(sp)
    li t0, 16
    add sp, sp, t0
    ret
.size __bswap_16, .-__bswap_16
.text
.globl __bswap_32
.type __bswap_32, @function
__bswap_32:
    li t0, -32
    add sp, sp, t0
    sd s2, 0(sp)
    sd s3, 8(sp)
    sd s4, 16(sp)
    mv t1, a0
    li t2, 255
    and t3, t1, t2
    li t2, 24
    sllw s2, t3, t2
    li t3, 65280
    and s3, t1, t3
    li t3, 8
    sllw s4, s3, t3
    or s3, s2, s4
    li s4, 16711680
    and s2, t1, s4
    srlw s4, s2, t3
    li s2, 4278190080
    and t3, t1, s2
    srlw s2, t3, t2
    or t2, s4, s2
    or s4, s3, t2
    mv a0, s4
    ld s2, 0(sp)
    ld s3, 8(sp)
    ld s4, 16(sp)
    li t0, 32
    add sp, sp, t0
    ret
.size __bswap_32, .-__bswap_32
.text
.globl __bswap_64
.type __bswap_64, @function
__bswap_64:
    li t0, -48
    add sp, sp, t0
    sd s2, 0(sp)
    sd s3, 8(sp)
    sd s4, 16(sp)
    sd s5, 24(sp)
    sd s6, 32(sp)
    sd s7, 40(sp)
    mv t1, a0
    li t2, 255
    and t3, t1, t2
    li t2, 56
    sll s2, t3, t2
    li t3, 65280
    and s3, t1, t3
    li t3, 40
    sll s4, s3, t3
    or s3, s2, s4
    li s4, 16711680
    and s2, t1, s4
    li s4, 24
    sll s5, s2, s4
    li s2, 4278190080
    and s6, t1, s2
    li s2, 8
    sll s7, s6, s2
    or s6, s5, s7
    or s7, s3, s6
    li s6, 1095216660480
    and s3, t1, s6
    srl s6, s3, s2
    li s3, 280375465082880
    and s2, t1, s3
    srl s3, s2, s4
    or s2, s6, s3
    li s3, 71776119061217280
    and s6, t1, s3
    srl s3, s6, t3
    li s6, -72057594037927936
    and t3, t1, s6
    srl s6, t3, t2
    or t2, s3, s6
    or s3, s2, t2
    or s2, s7, s3
    mv a0, s2
    ld s2, 0(sp)
    ld s3, 8(sp)
    ld s4, 16(sp)
    ld s5, 24(sp)
    ld s6, 32(sp)
    ld s7, 40(sp)
    li t0, 48
    add sp, sp, t0
    ret
.size __bswap_64, .-__bswap_64
.text
.globl __uint16_identity
.type __uint16_identity, @function
__uint16_identity:
    mv t1, a0
    mv a0, t1
    ret
.size __uint16_identity, .-__uint16_identity
.text
.globl __uint32_identity
.type __uint32_identity, @function
__uint32_identity:
    mv t1, a0
    mv a0, t1
    ret
.size __uint32_identity, .-__uint32_identity
.text
.globl __uint64_identity
.type __uint64_identity, @function
__uint64_identity:
    mv t1, a0
    mv a0, t1
    ret
.size __uint64_identity, .-__uint64_identity
.text
.globl foo
.type foo, @function
foo:
    li t0, -48
    add sp, sp, t0
    sd s2, 0(sp)
    sd s3, 8(sp)
    sd s4, 16(sp)
    sd s5, 24(sp)
    sd ra, 32(sp)
    mv s2, a0
    mv s3, a1
    li t1, 0
    xor t2, s2, t1
    seqz t2, t2
    beqz t2, .Lfoo_0
    slli t2, s3, 48
    srai t2, t2, 48
    mv a0, t2
    call __bswap_16
    mv t2, a0
    mv t1, t2
    slli t2, t1, 48
    srli t2, t2, 48
    mv s4, t2
    j .Lfoo_1
.Lfoo_0:
    li t2, 1
    xor t1, s2, t2
    seqz t1, t1
    beqz t1, .Lfoo_2
    sext.w t1, s3
    mv a0, t1
    call __bswap_32
    mv t1, a0
    mv t2, t1
    slli t1, t2, 32
    srli t1, t1, 32
    mv s5, t1
    j .Lfoo_3
.Lfoo_2:
    li t1, 2
    xor t2, s2, t1
    seqz t2, t2
    beqz t2, .Lfoo_4
    mv a0, s3
    call __bswap_64
    mv s3, a0
    mv t1, s3
    mv s3, t1
    j .Lfoo_5
.Lfoo_4:
    li t1, 0
    mv s3, t1
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
    li t0, 48
    add sp, sp, t0
    ret
.size foo, .-foo
