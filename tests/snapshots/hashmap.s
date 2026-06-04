.text
.globl error
.type error, @function
error:
    addi sp, sp, -80
    sd s2, 0(sp)
    sd ra, 8(sp)
    sd a0, 16(sp)
    sd a1, 24(sp)
    sd a2, 32(sp)
    sd a3, 40(sp)
    sd a4, 48(sp)
    sd a5, 56(sp)
    sd a6, 64(sp)
    sd a7, 72(sp)
    mv t0, a0
    la s2, stderr
    ld t1, 0(s2)
    addi t2, sp, 24
    mv a0, t1
    mv a1, t0
    mv a2, t2
    call vfprintf
    mv t1, a0
    ld t1, 0(s2)
    la s2, .Lstr29
    mv a0, t1
    mv a1, s2
    call fprintf
    mv s2, a0
    li s2, 1
    mv a0, s2
    call exit
    mv s2, a0
    ld ra, 8(sp)
    ld s2, 0(sp)
    addi sp, sp, 80
    ret
.size error, .-error
.text
.globl format
.type format, @function
format:
    addi sp, sp, -112
    sd s2, 0(sp)
    sd s3, 8(sp)
    sd s4, 16(sp)
    sd ra, 24(sp)
    sd a0, 48(sp)
    sd a1, 56(sp)
    sd a2, 64(sp)
    sd a3, 72(sp)
    sd a4, 80(sp)
    sd a5, 88(sp)
    sd a6, 96(sp)
    sd a7, 104(sp)
    mv s2, a0
    addi s3, sp, 32
    addi t0, sp, 40
    mv a0, s3
    mv a1, t0
    call open_memstream
    mv t0, a0
    mv s4, t0
    addi t0, sp, 56
    mv a0, s4
    mv a1, s2
    mv a2, t0
    call vfprintf
    mv t0, a0
    mv a0, s4
    call fclose
    mv t0, a0
    ld t0, 0(s3)
    mv a0, t0
    ld ra, 24(sp)
    ld s2, 0(sp)
    ld s3, 8(sp)
    ld s4, 16(sp)
    addi sp, sp, 112
    ret
.size format, .-format
.text
.globl fnv_hash
.type fnv_hash, @function
fnv_hash:
    addi sp, sp, -144
    sd s2, 64(sp)
    sd s3, 72(sp)
    sd s4, 80(sp)
    sd s5, 88(sp)
    sd s6, 96(sp)
    sd s7, 104(sp)
    sd s8, 112(sp)
    sd s9, 120(sp)
    sd s10, 128(sp)
    sd s11, 136(sp)
    mv t0, a0
    mv t1, a1
    li t2, -3750763034362895579
    li t3, 0
    li s2, 0
    mv s3, t0
    mv t0, t1
    mv t1, t2
    mv t2, t3
    mv t3, s2
.Lfnv_hash_0:
    slt s4, t2, t0
    sltu s5, s2, s4
    xor s6, t3, s2
    seqz s6, s6
    and s7, s5, s6
    beqz s7, .Lfnv_hash_1
    li s8, 1099511628211
    mul s9, t1, s8
    mv s10, t2
    add s11, s3, s10
    lb t4, 0(s11)
    sd t4, 0(sp)
    ld t5, 0(sp)
    andi t4, t5, 255
    sd t4, 8(sp)
    ld t5, 8(sp)
    mv t4, t5
    sd t4, 16(sp)
    ld t6, 16(sp)
    xor t4, s9, t6
    sd t4, 24(sp)
    li t4, 1
    sd t4, 32(sp)
    ld t6, 32(sp)
    addw t4, t2, t6
    sd t4, 40(sp)
    mv t4, s3
    sd t4, 48(sp)
    mv t4, t0
    sd t4, 56(sp)
    ld t5, 48(sp)
    mv s3, t5
    ld t5, 56(sp)
    mv t0, t5
    ld t5, 24(sp)
    mv t1, t5
    ld t5, 40(sp)
    mv t2, t5
    mv t3, s2
    j .Lfnv_hash_0
.Lfnv_hash_1:
    mv t0, t1
    mv a0, t0
    ld s2, 64(sp)
    ld s3, 72(sp)
    ld s4, 80(sp)
    ld s5, 88(sp)
    ld s6, 96(sp)
    ld s7, 104(sp)
    ld s8, 112(sp)
    ld s9, 120(sp)
    ld s10, 128(sp)
    ld s11, 136(sp)
    addi sp, sp, 144
    ret
.size fnv_hash, .-fnv_hash
.text
.globl rehash
.type rehash, @function
rehash:
    addi sp, sp, -736
    sd s2, 600(sp)
    sd s3, 608(sp)
    sd s4, 616(sp)
    sd s5, 624(sp)
    sd s6, 632(sp)
    sd s7, 640(sp)
    sd s8, 648(sp)
    sd s9, 656(sp)
    sd s10, 664(sp)
    sd s11, 672(sp)
    sd ra, 680(sp)
    mv s2, a0
    li s3, 0
    addi s4, sp, 688
    li t0, 118
    sb t0, 0(s4)
    li s5, 1
    add t0, s4, s5
    li t1, 111
    sb t1, 0(t0)
    li t1, 2
    add t0, s4, t1
    li t1, 105
    sb t1, 0(t0)
    li t1, 3
    add t0, s4, t1
    li t1, 100
    sb t1, 0(t0)
    li t1, 4
    add t0, s4, t1
    li t1, 32
    sb t1, 0(t0)
    li t0, 5
    add t2, s4, t0
    li t0, 114
    sb t0, 0(t2)
    li t0, 6
    add t2, s4, t0
    li t0, 101
    sb t0, 0(t2)
    li t0, 7
    add t2, s4, t0
    li t0, 104
    sb t0, 0(t2)
    li s6, 8
    add t2, s4, s6
    li t3, 97
    sb t3, 0(t2)
    li t2, 9
    add s7, s4, t2
    li t2, 115
    sb t2, 0(s7)
    li s7, 10
    add s8, s4, s7
    sb t0, 0(s8)
    li s8, 11
    add s7, s4, s8
    li s8, 40
    sb s8, 0(s7)
    li s8, 12
    add s7, s4, s8
    li s9, 72
    sb s9, 0(s7)
    li s9, 13
    add s7, s4, s9
    sb t3, 0(s7)
    li s7, 14
    add s9, s4, s7
    sb t2, 0(s9)
    li s7, 15
    add s9, s4, s7
    sb t0, 0(s9)
    li s7, 16
    add s9, s4, s7
    li t0, 77
    sb t0, 0(s9)
    li t0, 17
    add s9, s4, t0
    sb t3, 0(s9)
    li t0, 18
    add s9, s4, t0
    li t0, 112
    sb t0, 0(s9)
    li t0, 19
    add s9, s4, t0
    sb t1, 0(s9)
    li t0, 20
    add s9, s4, t0
    li t0, 42
    sb t0, 0(s9)
    li t0, 21
    add s9, s4, t0
    li t0, 41
    sb t0, 0(s9)
    li t0, 22
    add s9, s4, t0
    li t0, 0
    sb t0, 0(s9)
    li s9, 0
    li s10, 24
    li s11, -1
    mv t0, s2
    mv t1, s9
    mv t3, s9
    mv t2, s4
    mv t4, s3
    sd t4, 0(sp)
.Lrehash_0:
    add t4, t0, s6
    sd t4, 8(sp)
    ld t5, 8(sp)
    lw t4, 0(t5)
    sd t4, 16(sp)
    ld t6, 16(sp)
    slt t4, t1, t6
    sd t4, 24(sp)
    ld t6, 24(sp)
    sltu t4, s3, t6
    sd t4, 32(sp)
    ld t5, 0(sp)
    xor t4, t5, s3
    sd t4, 40(sp)
    ld t5, 40(sp)
    seqz t4, t5
    sd t4, 40(sp)
    ld t5, 32(sp)
    ld t6, 40(sp)
    and t4, t5, t6
    sd t4, 48(sp)
    ld t5, 48(sp)
    beqz t5, .Lrehash_1
    addw t4, t1, s5
    sd t4, 56(sp)
    ld t4, 0(t0)
    sd t4, 64(sp)
    mv t4, t1
    sd t4, 72(sp)
    ld t5, 72(sp)
    mul t4, t5, s10
    sd t4, 80(sp)
    ld t5, 64(sp)
    ld t6, 80(sp)
    add t4, t5, t6
    sd t4, 88(sp)
    ld t5, 88(sp)
    ld t4, 0(t5)
    sd t4, 96(sp)
    ld t6, 96(sp)
    sltu t4, s3, t6
    sd t4, 104(sp)
    ld t5, 104(sp)
    beqz t5, .Lrehash_2
    ld t5, 96(sp)
    xor t4, t5, s11
    sd t4, 112(sp)
    ld t5, 112(sp)
    seqz t4, t5
    sd t4, 112(sp)
    ld t5, 112(sp)
    xor t4, t5, s3
    sd t4, 120(sp)
    ld t5, 120(sp)
    seqz t4, t5
    sd t4, 120(sp)
    ld t6, 120(sp)
    sltu t4, s3, t6
    sd t4, 128(sp)
    ld t5, 128(sp)
    mv t4, t5
    sd t4, 136(sp)
    j .Lrehash_3
.Lrehash_2:
    mv t4, s3
    sd t4, 136(sp)
.Lrehash_3:
    ld t6, 136(sp)
    sltu t4, s3, t6
    sd t4, 144(sp)
    ld t5, 144(sp)
    beqz t5, .Lrehash_4
    addw t4, t3, s5
    sd t4, 152(sp)
    ld t5, 152(sp)
    mv t4, t5
    sd t4, 160(sp)
    j .Lrehash_5
.Lrehash_4:
    mv t4, t3
    sd t4, 160(sp)
.Lrehash_5:
    mv t4, t0
    sd t4, 168(sp)
    mv t4, t2
    sd t4, 176(sp)
    ld t5, 168(sp)
    mv t0, t5
    ld t5, 56(sp)
    mv t1, t5
    ld t5, 160(sp)
    mv t3, t5
    ld t5, 176(sp)
    mv t2, t5
    mv t4, s3
    sd t4, 0(sp)
    j .Lrehash_0
.Lrehash_1:
    mv t4, t3
    sd t4, 184(sp)
    mv t3, t1
    add t4, s2, s6
    sd t4, 192(sp)
    ld t5, 192(sp)
    lw t1, 0(t5)
    mv t2, s2
    mv t0, t3
    ld t5, 184(sp)
    mv t3, t5
    mv t4, t1
    sd t4, 200(sp)
    mv t1, s4
    mv t4, s3
    sd t4, 208(sp)
.Lrehash_6:
    li t4, 100
    sd t4, 216(sp)
    ld t6, 216(sp)
    mulw t4, t3, t6
    sd t4, 224(sp)
    ld t5, 224(sp)
    ld t6, 200(sp)
    divw t4, t5, t6
    sd t4, 232(sp)
    li t4, 50
    sd t4, 240(sp)
    ld t5, 232(sp)
    ld t6, 240(sp)
    slt t4, t5, t6
    sd t4, 248(sp)
    ld t5, 248(sp)
    xor t4, t5, s3
    sd t4, 256(sp)
    ld t5, 256(sp)
    seqz t4, t5
    sd t4, 256(sp)
    ld t6, 256(sp)
    sltu t4, s3, t6
    sd t4, 264(sp)
    ld t5, 208(sp)
    xor t4, t5, s3
    sd t4, 272(sp)
    ld t5, 272(sp)
    seqz t4, t5
    sd t4, 272(sp)
    ld t5, 264(sp)
    ld t6, 272(sp)
    and t4, t5, t6
    sd t4, 280(sp)
    ld t5, 280(sp)
    beqz t5, .Lrehash_7
    ld t5, 200(sp)
    sllw t4, t5, s5
    sd t4, 288(sp)
    mv t4, t2
    sd t4, 296(sp)
    mv t4, t0
    sd t4, 304(sp)
    mv t4, t3
    sd t4, 312(sp)
    mv t4, t1
    sd t4, 320(sp)
    ld t5, 296(sp)
    mv t2, t5
    ld t5, 304(sp)
    mv t0, t5
    ld t5, 312(sp)
    mv t3, t5
    ld t5, 288(sp)
    mv t4, t5
    sd t4, 200(sp)
    ld t5, 320(sp)
    mv t1, t5
    mv t4, s3
    sd t4, 208(sp)
    j .Lrehash_6
.Lrehash_7:
    ld t5, 200(sp)
    mv t4, t5
    sd t4, 328(sp)
    ld t6, 328(sp)
    slt t3, s9, t6
    sltu t2, s3, t3
    la t4, .Lstr31
    sd t4, 336(sp)
    beqz t2, .Lrehash_8
    j .Lrehash_9
.Lrehash_8:
    la t2, .Lstr30
    li t3, 59
    mv a0, t2
    ld t5, 336(sp)
    mv a1, t5
    mv a2, t3
    mv a3, s4
    call __assert_fail
    mv t3, a0
.Lrehash_9:
    addi t4, sp, 712
    sd t4, 344(sp)
    ld t6, 344(sp)
    sd s3, 0(t6)
    ld t5, 344(sp)
    add t4, t5, s6
    sd t4, 352(sp)
    ld t6, 352(sp)
    sw s9, 0(t6)
    ld t5, 344(sp)
    add t4, t5, s8
    sd t4, 360(sp)
    ld t6, 360(sp)
    sw s9, 0(t6)
    ld t5, 328(sp)
    mv s8, t5
    li t3, 24
    mv a0, s8
    mv a1, t3
    call calloc
    mv t3, a0
    mv s8, t3
    ld t6, 344(sp)
    sd s8, 0(t6)
    ld t5, 328(sp)
    ld t6, 352(sp)
    sw t5, 0(t6)
    mv s8, s2
    mv t4, s9
    sd t4, 368(sp)
    ld t5, 184(sp)
    mv s9, t5
    ld t5, 328(sp)
    mv t4, t5
    sd t4, 376(sp)
    mv t4, s4
    sd t4, 384(sp)
    ld t5, 344(sp)
    mv t4, t5
    sd t4, 392(sp)
    mv t4, s3
    sd t4, 400(sp)
.Lrehash_10:
    add t4, s8, s6
    sd t4, 408(sp)
    ld t5, 408(sp)
    lw t4, 0(t5)
    sd t4, 416(sp)
    ld t5, 368(sp)
    ld t6, 416(sp)
    slt t4, t5, t6
    sd t4, 424(sp)
    ld t6, 424(sp)
    sltu t4, s3, t6
    sd t4, 432(sp)
    ld t5, 400(sp)
    xor t4, t5, s3
    sd t4, 440(sp)
    ld t5, 440(sp)
    seqz t4, t5
    sd t4, 440(sp)
    ld t5, 432(sp)
    ld t6, 440(sp)
    and t4, t5, t6
    sd t4, 448(sp)
    ld t5, 448(sp)
    beqz t5, .Lrehash_11
    ld t4, 0(s8)
    sd t4, 456(sp)
    ld t5, 368(sp)
    mv t4, t5
    sd t4, 464(sp)
    ld t5, 464(sp)
    mul t4, t5, s10
    sd t4, 472(sp)
    ld t5, 456(sp)
    ld t6, 472(sp)
    add t4, t5, t6
    sd t4, 480(sp)
    ld t5, 480(sp)
    ld t4, 0(t5)
    sd t4, 488(sp)
    ld t6, 488(sp)
    sltu t4, s3, t6
    sd t4, 496(sp)
    ld t5, 496(sp)
    beqz t5, .Lrehash_12
    ld t5, 488(sp)
    xor t4, t5, s11
    sd t4, 504(sp)
    ld t5, 504(sp)
    seqz t4, t5
    sd t4, 504(sp)
    ld t5, 504(sp)
    xor t4, t5, s3
    sd t4, 512(sp)
    ld t5, 512(sp)
    seqz t4, t5
    sd t4, 512(sp)
    ld t6, 512(sp)
    sltu t4, s3, t6
    sd t4, 520(sp)
    ld t5, 520(sp)
    mv t4, t5
    sd t4, 528(sp)
    j .Lrehash_13
.Lrehash_12:
    mv t4, s3
    sd t4, 528(sp)
.Lrehash_13:
    ld t6, 528(sp)
    sltu t4, s3, t6
    sd t4, 536(sp)
    ld t5, 536(sp)
    beqz t5, .Lrehash_14
    ld t5, 480(sp)
    add t4, t5, s6
    sd t4, 544(sp)
    ld t5, 544(sp)
    lw t4, 0(t5)
    sd t4, 552(sp)
    ld t5, 480(sp)
    add t4, t5, s7
    sd t4, 560(sp)
    ld t5, 560(sp)
    ld t4, 0(t5)
    sd t4, 568(sp)
    ld t5, 392(sp)
    mv a0, t5
    ld t5, 488(sp)
    mv a1, t5
    ld t5, 552(sp)
    mv a2, t5
    ld t5, 568(sp)
    mv a3, t5
    call hashmap_put2
    mv t3, a0
    j .Lrehash_15
.Lrehash_14:
.Lrehash_15:
    ld t5, 368(sp)
    addw t2, t5, s5
    mv t1, s8
    mv t0, s9
    ld t5, 376(sp)
    mv t4, t5
    sd t4, 576(sp)
    ld t5, 384(sp)
    mv t4, t5
    sd t4, 584(sp)
    ld t5, 392(sp)
    mv t4, t5
    sd t4, 592(sp)
    mv s8, t1
    mv t4, t2
    sd t4, 368(sp)
    mv s9, t0
    ld t5, 576(sp)
    mv t4, t5
    sd t4, 376(sp)
    ld t5, 584(sp)
    mv t4, t5
    sd t4, 384(sp)
    ld t5, 592(sp)
    mv t4, t5
    sd t4, 392(sp)
    mv t4, s3
    sd t4, 400(sp)
    j .Lrehash_10
.Lrehash_11:
    ld t5, 360(sp)
    lw s7, 0(t5)
    ld t5, 184(sp)
    xor s11, t5, s7
    seqz s11, s11
    sltu s7, s3, s11
    beqz s7, .Lrehash_16
    j .Lrehash_17
.Lrehash_16:
    la s11, .Lstr32
    li s7, 72
    mv a0, s11
    ld t5, 336(sp)
    mv a1, t5
    mv a2, s7
    mv a3, s4
    call __assert_fail
    mv s11, a0
.Lrehash_17:
    ld t5, 344(sp)
    ld s11, 0(t5)
    sd s11, 0(s2)
    ld t5, 352(sp)
    ld s11, 0(t5)
    ld t6, 192(sp)
    sd s11, 0(t6)
    ld ra, 680(sp)
    ld s2, 600(sp)
    ld s3, 608(sp)
    ld s4, 616(sp)
    ld s5, 624(sp)
    ld s6, 632(sp)
    ld s7, 640(sp)
    ld s8, 648(sp)
    ld s9, 656(sp)
    ld s10, 664(sp)
    ld s11, 672(sp)
    addi sp, sp, 736
    ret
.size rehash, .-rehash
.text
.globl match
.type match, @function
match:
    addi sp, sp, -32
    sd s2, 0(sp)
    sd s3, 8(sp)
    sd s4, 16(sp)
    sd ra, 24(sp)
    mv t0, a0
    mv t1, a2
    mv t2, a1
    li s2, 0
    ld t3, 0(t0)
    sltu s3, s2, t3
    beqz s3, .Lmatch_0
    li s3, -1
    xor s4, t3, s3
    seqz s4, s4
    xor s3, s4, s2
    seqz s3, s3
    sltu s4, s2, s3
    mv s3, s4
    j .Lmatch_1
.Lmatch_0:
    mv s3, s2
.Lmatch_1:
    sltu s4, s2, s3
    beqz s4, .Lmatch_2
    li s4, 8
    add s3, t0, s4
    lw s4, 0(s3)
    xor s3, t1, s4
    seqz s3, s3
    sltu s4, s2, s3
    mv s3, s4
    j .Lmatch_3
.Lmatch_2:
    mv s3, s2
.Lmatch_3:
    sltu s4, s2, s3
    beqz s4, .Lmatch_4
    mv s4, t1
    mv a0, t3
    mv a1, t2
    mv a2, s4
    call memcmp
    mv t2, a0
    mv t1, t2
    li t2, 0
    xor s4, t1, t2
    seqz s4, s4
    sltu t2, s2, s4
    mv s4, t2
    j .Lmatch_5
.Lmatch_4:
    mv s4, s2
.Lmatch_5:
    sltu t2, s2, s4
    mv a0, t2
    ld ra, 24(sp)
    ld s2, 0(sp)
    ld s3, 8(sp)
    ld s4, 16(sp)
    addi sp, sp, 32
    ret
.size match, .-match
.text
.globl get_entry
.type get_entry, @function
get_entry:
    addi sp, sp, -352
    sd s2, 256(sp)
    sd s3, 264(sp)
    sd s4, 272(sp)
    sd s5, 280(sp)
    sd s6, 288(sp)
    sd s7, 296(sp)
    sd s8, 304(sp)
    sd s9, 312(sp)
    sd s10, 320(sp)
    sd s11, 328(sp)
    sd ra, 336(sp)
    mv s2, a0
    mv s3, a1
    mv s4, a2
    li s5, 0
    ld t0, 0(s2)
    xor t1, t0, s5
    seqz t1, t1
    sltu t0, s5, t1
    beqz t0, .Lget_entry_0
    mv s6, s5
    j .Lget_entry_1
.Lget_entry_0:
    xor s7, t0, s5
    seqz s7, s7
    mv a0, s3
    mv a1, s4
    call fnv_hash
    mv t0, a0
    mv t1, t0
    li t0, 0
    mv s8, s2
    mv s2, s4
    mv s4, t1
    mv s9, s3
    mv s3, t0
    mv s10, s5
    mv s11, s5
    mv t4, s5
    sd t4, 0(sp)
.Lget_entry_2:
    li t4, 8
    sd t4, 8(sp)
    ld t6, 8(sp)
    add t4, s8, t6
    sd t4, 16(sp)
    ld t5, 16(sp)
    lw t4, 0(t5)
    sd t4, 24(sp)
    ld t6, 24(sp)
    slt t4, s3, t6
    sd t4, 32(sp)
    ld t6, 32(sp)
    sltu t4, s5, t6
    sd t4, 40(sp)
    xor t4, s10, s5
    sd t4, 48(sp)
    ld t5, 48(sp)
    seqz t4, t5
    sd t4, 48(sp)
    ld t5, 40(sp)
    ld t6, 48(sp)
    and t4, t5, t6
    sd t4, 56(sp)
    xor t4, s11, s5
    sd t4, 64(sp)
    ld t5, 64(sp)
    seqz t4, t5
    sd t4, 64(sp)
    ld t5, 56(sp)
    ld t6, 64(sp)
    and t4, t5, t6
    sd t4, 72(sp)
    ld t5, 72(sp)
    beqz t5, .Lget_entry_3
    ld t4, 0(s8)
    sd t4, 80(sp)
    mv t4, s3
    sd t4, 88(sp)
    ld t6, 88(sp)
    add t4, s4, t6
    sd t4, 96(sp)
    ld t5, 24(sp)
    mv t4, t5
    sd t4, 104(sp)
    ld t5, 96(sp)
    ld t6, 104(sp)
    remu t4, t5, t6
    sd t4, 112(sp)
    li t4, 24
    sd t4, 120(sp)
    ld t5, 112(sp)
    ld t6, 120(sp)
    mul t4, t5, t6
    sd t4, 128(sp)
    ld t5, 80(sp)
    ld t6, 128(sp)
    add t4, t5, t6
    sd t4, 136(sp)
    ld t5, 136(sp)
    mv a0, t5
    mv a1, s9
    mv a2, s2
    call match
    mv t0, a0
    li t1, 1
    addw t2, s3, t1
    mv t3, t0
    andi t4, t3, 1
    sd t4, 144(sp)
    ld t6, 144(sp)
    sltu t4, s5, t6
    sd t4, 152(sp)
    ld t5, 152(sp)
    xor t4, t5, s5
    sd t4, 160(sp)
    ld t5, 160(sp)
    seqz t4, t5
    sd t4, 160(sp)
    ld t5, 136(sp)
    ld t4, 0(t5)
    sd t4, 168(sp)
    li t4, 0
    sd t4, 176(sp)
    ld t5, 168(sp)
    ld t6, 176(sp)
    xor t4, t5, t6
    sd t4, 184(sp)
    ld t5, 184(sp)
    seqz t4, t5
    sd t4, 184(sp)
    ld t6, 184(sp)
    sltu t4, s5, t6
    sd t4, 192(sp)
    ld t5, 160(sp)
    ld t6, 192(sp)
    and t4, t5, t6
    sd t4, 200(sp)
    ld t5, 152(sp)
    ld t6, 200(sp)
    add t4, t5, t6
    sd t4, 208(sp)
    ld t5, 152(sp)
    beqz t5, .Lget_entry_4
    ld t5, 136(sp)
    mv t4, t5
    sd t4, 216(sp)
    j .Lget_entry_5
.Lget_entry_4:
    mv t4, s5
    sd t4, 216(sp)
.Lget_entry_5:
    mv t4, s8
    sd t4, 224(sp)
    mv t4, s2
    sd t4, 232(sp)
    mv t4, s4
    sd t4, 240(sp)
    mv t4, s9
    sd t4, 248(sp)
    ld t5, 224(sp)
    mv s8, t5
    ld t5, 232(sp)
    mv s2, t5
    ld t5, 240(sp)
    mv s4, t5
    ld t5, 248(sp)
    mv s9, t5
    mv s3, t2
    mv s10, s5
    ld t5, 208(sp)
    mv s11, t5
    ld t5, 216(sp)
    mv t4, t5
    sd t4, 0(sp)
    j .Lget_entry_2
.Lget_entry_3:
    mv s2, s11
    and s11, s7, s2
    beqz s11, .Lget_entry_6
    ld t5, 0(sp)
    mv s7, t5
    mv s11, s7
    j .Lget_entry_7
.Lget_entry_6:
    la s7, .Lstr33
    la s2, .Lstr31
    li s4, 94
    mv a0, s7
    mv a1, s2
    mv a2, s4
    call error
    mv s2, a0
    mv s11, s5
.Lget_entry_7:
    mv s6, s11
.Lget_entry_1:
    mv a0, s6
    ld ra, 336(sp)
    ld s2, 256(sp)
    ld s3, 264(sp)
    ld s4, 272(sp)
    ld s5, 280(sp)
    ld s6, 288(sp)
    ld s7, 296(sp)
    ld s8, 304(sp)
    ld s9, 312(sp)
    ld s10, 320(sp)
    ld s11, 328(sp)
    addi sp, sp, 352
    ret
.size get_entry, .-get_entry
.text
.globl get_or_insert_entry
.type get_or_insert_entry, @function
get_or_insert_entry:
    addi sp, sp, -416
    sd s2, 328(sp)
    sd s3, 336(sp)
    sd s4, 344(sp)
    sd s5, 352(sp)
    sd s6, 360(sp)
    sd s7, 368(sp)
    sd s8, 376(sp)
    sd s9, 384(sp)
    sd s10, 392(sp)
    sd s11, 400(sp)
    sd ra, 408(sp)
    mv s2, a0
    mv s3, a1
    mv s4, a2
    li s5, 0
    ld t0, 0(s2)
    xor t1, t0, s5
    seqz t1, t1
    sltu t0, s5, t1
    li s6, 8
    add s7, s2, s6
    li s8, 12
    beqz t0, .Lget_or_insert_entry_0
    li t0, 16
    li t1, 24
    mv a0, t0
    mv a1, t1
    call calloc
    mv t1, a0
    mv t0, t1
    sd t0, 0(s2)
    li t0, 16
    sw t0, 0(s7)
    j .Lget_or_insert_entry_1
.Lget_or_insert_entry_0:
    add t0, s2, s8
    lw t1, 0(t0)
    li t0, 100
    mulw t2, t1, t0
    lw t0, 0(s7)
    divw s7, t2, t0
    li t2, 70
    slt t0, s7, t2
    xor t2, t0, s5
    seqz t2, t2
    sltu t0, s5, t2
    beqz t0, .Lget_or_insert_entry_2
    mv a0, s2
    call rehash
    mv t0, a0
    j .Lget_or_insert_entry_3
.Lget_or_insert_entry_2:
.Lget_or_insert_entry_3:
.Lget_or_insert_entry_1:
    mv a0, s3
    mv a1, s4
    call fnv_hash
    mv t0, a0
    mv t2, t0
    li t0, 0
    mv s7, s2
    mv s2, s4
    mv s4, t2
    mv s9, s3
    mv s3, t0
    mv s10, s5
    mv s11, s5
    mv t4, s5
    sd t4, 0(sp)
.Lget_or_insert_entry_4:
    add t4, s7, s6
    sd t4, 8(sp)
    ld t5, 8(sp)
    lw t4, 0(t5)
    sd t4, 16(sp)
    ld t6, 16(sp)
    slt t4, s3, t6
    sd t4, 24(sp)
    ld t6, 24(sp)
    sltu t4, s5, t6
    sd t4, 32(sp)
    xor t4, s10, s5
    sd t4, 40(sp)
    ld t5, 40(sp)
    seqz t4, t5
    sd t4, 40(sp)
    ld t5, 32(sp)
    ld t6, 40(sp)
    and t4, t5, t6
    sd t4, 48(sp)
    xor t4, s11, s5
    sd t4, 56(sp)
    ld t5, 56(sp)
    seqz t4, t5
    sd t4, 56(sp)
    ld t5, 48(sp)
    ld t6, 56(sp)
    and t4, t5, t6
    sd t4, 64(sp)
    ld t5, 64(sp)
    beqz t5, .Lget_or_insert_entry_5
    ld t4, 0(s7)
    sd t4, 72(sp)
    mv t4, s3
    sd t4, 80(sp)
    ld t6, 80(sp)
    add t4, s4, t6
    sd t4, 88(sp)
    ld t5, 16(sp)
    mv t4, t5
    sd t4, 96(sp)
    ld t5, 88(sp)
    ld t6, 96(sp)
    remu t4, t5, t6
    sd t4, 104(sp)
    li t4, 24
    sd t4, 112(sp)
    ld t5, 104(sp)
    ld t6, 112(sp)
    mul t4, t5, t6
    sd t4, 120(sp)
    ld t5, 72(sp)
    ld t6, 120(sp)
    add t4, t5, t6
    sd t4, 128(sp)
    ld t5, 128(sp)
    mv a0, t5
    mv a1, s9
    mv a2, s2
    call match
    mv t0, a0
    mv t2, t0
    andi t1, t2, 1
    sltu t3, s5, t1
    xor t4, t3, s5
    sd t4, 136(sp)
    ld t5, 136(sp)
    seqz t4, t5
    sd t4, 136(sp)
    ld t5, 128(sp)
    ld t4, 0(t5)
    sd t4, 144(sp)
    li t4, -1
    sd t4, 152(sp)
    ld t5, 144(sp)
    ld t6, 152(sp)
    xor t4, t5, t6
    sd t4, 160(sp)
    ld t5, 160(sp)
    seqz t4, t5
    sd t4, 160(sp)
    ld t6, 160(sp)
    sltu t4, s5, t6
    sd t4, 168(sp)
    ld t5, 168(sp)
    xor t4, t5, s5
    sd t4, 176(sp)
    ld t5, 176(sp)
    seqz t4, t5
    sd t4, 176(sp)
    ld t5, 136(sp)
    ld t6, 176(sp)
    and t4, t5, t6
    sd t4, 184(sp)
    li t4, 0
    sd t4, 192(sp)
    ld t5, 144(sp)
    ld t6, 192(sp)
    xor t4, t5, t6
    sd t4, 200(sp)
    ld t5, 200(sp)
    seqz t4, t5
    sd t4, 200(sp)
    ld t6, 200(sp)
    sltu t4, s5, t6
    sd t4, 208(sp)
    ld t5, 184(sp)
    ld t6, 208(sp)
    and t4, t5, t6
    sd t4, 216(sp)
    ld t5, 136(sp)
    ld t6, 168(sp)
    and t4, t5, t6
    sd t4, 224(sp)
    ld t6, 224(sp)
    add t4, t3, t6
    sd t4, 232(sp)
    ld t5, 216(sp)
    ld t6, 232(sp)
    add t4, t5, t6
    sd t4, 240(sp)
    li t4, 1
    sd t4, 248(sp)
    ld t5, 240(sp)
    beqz t5, .Lget_or_insert_entry_6
    beqz t3, .Lget_or_insert_entry_8
    j .Lget_or_insert_entry_9
.Lget_or_insert_entry_8:
    ld t6, 128(sp)
    sd s9, 0(t6)
    ld t5, 128(sp)
    add t4, t5, s6
    sd t4, 256(sp)
    ld t6, 256(sp)
    sw s2, 0(t6)
    ld t5, 224(sp)
    beqz t5, .Lget_or_insert_entry_10
    j .Lget_or_insert_entry_11
.Lget_or_insert_entry_10:
    add t4, s7, s8
    sd t4, 264(sp)
    ld t5, 264(sp)
    lw t4, 0(t5)
    sd t4, 272(sp)
    ld t5, 272(sp)
    ld t6, 248(sp)
    addw t4, t5, t6
    sd t4, 280(sp)
    ld t5, 280(sp)
    ld t6, 264(sp)
    sw t5, 0(t6)
.Lget_or_insert_entry_11:
.Lget_or_insert_entry_9:
    j .Lget_or_insert_entry_7
.Lget_or_insert_entry_6:
.Lget_or_insert_entry_7:
    ld t6, 248(sp)
    addw t4, s3, t6
    sd t4, 288(sp)
    mv t4, s7
    sd t4, 296(sp)
    mv t4, s2
    sd t4, 304(sp)
    mv t4, s4
    sd t4, 312(sp)
    mv t4, s9
    sd t4, 320(sp)
    ld t5, 296(sp)
    mv s7, t5
    ld t5, 304(sp)
    mv s2, t5
    ld t5, 312(sp)
    mv s4, t5
    ld t5, 320(sp)
    mv s9, t5
    ld t5, 288(sp)
    mv s3, t5
    mv s10, s5
    ld t5, 240(sp)
    mv s11, t5
    ld t5, 128(sp)
    mv t4, t5
    sd t4, 0(sp)
    j .Lget_or_insert_entry_4
.Lget_or_insert_entry_5:
    mv s2, s11
    beqz s2, .Lget_or_insert_entry_12
    ld t5, 0(sp)
    mv s2, t5
    mv s11, s2
    j .Lget_or_insert_entry_13
.Lget_or_insert_entry_12:
    la s2, .Lstr33
    la s8, .Lstr31
    li s6, 126
    mv a0, s2
    mv a1, s8
    mv a2, s6
    call error
    mv s8, a0
    mv s11, s5
.Lget_or_insert_entry_13:
    mv a0, s11
    ld ra, 408(sp)
    ld s2, 328(sp)
    ld s3, 336(sp)
    ld s4, 344(sp)
    ld s5, 352(sp)
    ld s6, 360(sp)
    ld s7, 368(sp)
    ld s8, 376(sp)
    ld s9, 384(sp)
    ld s10, 392(sp)
    ld s11, 400(sp)
    addi sp, sp, 416
    ret
.size get_or_insert_entry, .-get_or_insert_entry
.text
.globl hashmap_get
.type hashmap_get, @function
hashmap_get:
    addi sp, sp, -32
    sd s2, 0(sp)
    sd s3, 8(sp)
    sd ra, 16(sp)
    mv s2, a1
    mv s3, a0
    mv a0, s2
    call strlen
    mv t0, a0
    mv t1, t0
    sext.w t0, t1
    mv a0, s3
    mv a1, s2
    mv a2, t0
    call hashmap_get2
    mv s3, a0
    mv t1, s3
    mv a0, t1
    ld ra, 16(sp)
    ld s2, 0(sp)
    ld s3, 8(sp)
    addi sp, sp, 32
    ret
.size hashmap_get, .-hashmap_get
.text
.globl hashmap_get2
.type hashmap_get2, @function
hashmap_get2:
    addi sp, sp, -16
    sd ra, 0(sp)
    mv t0, a0
    mv t1, a1
    mv t2, a2
    mv a0, t0
    mv a1, t1
    mv a2, t2
    call get_entry
    mv t1, a0
    li t2, 0
    mv t0, t1
    sltu t1, t2, t0
    beqz t1, .Lhashmap_get2_0
    li t1, 16
    add t2, t0, t1
    ld t1, 0(t2)
    mv t2, t1
    j .Lhashmap_get2_1
.Lhashmap_get2_0:
    li t1, 0
    mv t2, t1
.Lhashmap_get2_1:
    mv a0, t2
    ld ra, 0(sp)
    addi sp, sp, 16
    ret
.size hashmap_get2, .-hashmap_get2
.text
.globl hashmap_put
.type hashmap_put, @function
hashmap_put:
    addi sp, sp, -32
    sd s2, 0(sp)
    sd s3, 8(sp)
    sd s4, 16(sp)
    sd ra, 24(sp)
    mv s2, a1
    mv s3, a0
    mv s4, a2
    mv a0, s2
    call strlen
    mv t0, a0
    mv t1, t0
    sext.w t0, t1
    mv a0, s3
    mv a1, s2
    mv a2, t0
    mv a3, s4
    call hashmap_put2
    mv s3, a0
    ld ra, 24(sp)
    ld s2, 0(sp)
    ld s3, 8(sp)
    ld s4, 16(sp)
    addi sp, sp, 32
    ret
.size hashmap_put, .-hashmap_put
.text
.globl hashmap_put2
.type hashmap_put2, @function
hashmap_put2:
    addi sp, sp, -16
    sd s2, 0(sp)
    sd ra, 8(sp)
    mv t0, a0
    mv t1, a1
    mv t2, a2
    mv s2, a3
    mv a0, t0
    mv a1, t1
    mv a2, t2
    call get_or_insert_entry
    mv t2, a0
    mv t1, t2
    li t2, 16
    add t0, t1, t2
    sd s2, 0(t0)
    ld ra, 8(sp)
    ld s2, 0(sp)
    addi sp, sp, 16
    ret
.size hashmap_put2, .-hashmap_put2
.text
.globl hashmap_delete
.type hashmap_delete, @function
hashmap_delete:
    addi sp, sp, -32
    sd s2, 0(sp)
    sd s3, 8(sp)
    sd ra, 16(sp)
    mv s2, a1
    mv s3, a0
    mv a0, s2
    call strlen
    mv t0, a0
    mv t1, t0
    sext.w t0, t1
    mv a0, s3
    mv a1, s2
    mv a2, t0
    call hashmap_delete2
    mv s3, a0
    ld ra, 16(sp)
    ld s2, 0(sp)
    ld s3, 8(sp)
    addi sp, sp, 32
    ret
.size hashmap_delete, .-hashmap_delete
.text
.globl hashmap_delete2
.type hashmap_delete2, @function
hashmap_delete2:
    addi sp, sp, -16
    sd s2, 0(sp)
    sd ra, 8(sp)
    mv t0, a0
    mv t1, a1
    mv t2, a2
    li s2, 0
    mv a0, t0
    mv a1, t1
    mv a2, t2
    call get_entry
    mv t2, a0
    mv t1, t2
    sltu t2, s2, t1
    beqz t2, .Lhashmap_delete2_0
    li t2, -1
    sd t2, 0(t1)
    j .Lhashmap_delete2_1
.Lhashmap_delete2_0:
.Lhashmap_delete2_1:
    ld ra, 8(sp)
    ld s2, 0(sp)
    addi sp, sp, 16
    ret
.size hashmap_delete2, .-hashmap_delete2
.text
.globl foo
.type foo, @function
foo:
    addi sp, sp, -1120
    sd s2, 1016(sp)
    sd s3, 1024(sp)
    sd s4, 1032(sp)
    sd s5, 1040(sp)
    sd s6, 1048(sp)
    sd s7, 1056(sp)
    sd s8, 1064(sp)
    sd s9, 1072(sp)
    sd s10, 1080(sp)
    sd s11, 1088(sp)
    sd ra, 1096(sp)
    li s2, 0
    addi s3, sp, 1104
    li t0, 105
    sb t0, 0(s3)
    li s4, 1
    add t1, s3, s4
    li t2, 110
    sb t2, 0(t1)
    li t2, 2
    add t1, s3, t2
    li t2, 116
    sb t2, 0(t1)
    li t2, 3
    add t1, s3, t2
    li t2, 32
    sb t2, 0(t1)
    li t2, 4
    add t1, s3, t2
    li t2, 102
    sb t2, 0(t1)
    li t2, 5
    add t1, s3, t2
    li t2, 111
    sb t2, 0(t1)
    li t1, 6
    add t3, s3, t1
    sb t2, 0(t3)
    li t3, 7
    add t1, s3, t3
    li t3, 40
    sb t3, 0(t1)
    li t3, 8
    add t1, s3, t3
    li t3, 118
    sb t3, 0(t1)
    li t3, 9
    add t1, s3, t3
    sb t2, 0(t1)
    li t3, 10
    add t1, s3, t3
    sb t0, 0(t1)
    li t3, 11
    add t1, s3, t3
    li t3, 100
    sb t3, 0(t1)
    li t3, 12
    add t1, s3, t3
    li t3, 41
    sb t3, 0(t1)
    li t3, 13
    add t1, s3, t3
    li t3, 0
    sb t3, 0(t1)
    li t3, 1
    li t1, 16
    mv a0, t3
    mv a1, t1
    call calloc
    mv t1, a0
    mv s5, t1
    li s6, 0
    li s7, 5000
    la s8, .Lstr34
    mv s9, s5
    mv s10, s6
    mv s11, s3
    mv t4, s2
    sd t4, 0(sp)
.Lfoo_0:
    slt t4, s10, s7
    sd t4, 8(sp)
    ld t6, 8(sp)
    sltu t4, s2, t6
    sd t4, 16(sp)
    ld t5, 0(sp)
    xor t4, t5, s2
    sd t4, 24(sp)
    ld t5, 24(sp)
    seqz t4, t5
    sd t4, 24(sp)
    ld t5, 16(sp)
    ld t6, 24(sp)
    and t4, t5, t6
    sd t4, 32(sp)
    ld t5, 32(sp)
    beqz t5, .Lfoo_1
    mv a0, s8
    mv a1, s10
    call format
    mv t4, a0
    sd t4, 40(sp)
    ld t5, 40(sp)
    mv t4, t5
    sd t4, 48(sp)
    mv t4, s10
    sd t4, 56(sp)
    mv a0, s9
    ld t5, 48(sp)
    mv a1, t5
    ld t5, 56(sp)
    mv a2, t5
    call hashmap_put
    mv t1, a0
    addw t3, s10, s4
    mv t0, s9
    mv t2, s11
    mv s9, t0
    mv s10, t3
    mv s11, t2
    mv t4, s2
    sd t4, 0(sp)
    j .Lfoo_0
.Lfoo_1:
    li s10, 1000
    li s11, 2000
    mv s9, s5
    mv t4, s10
    sd t4, 64(sp)
    mv t4, s3
    sd t4, 72(sp)
    mv t4, s2
    sd t4, 80(sp)
.Lfoo_2:
    ld t5, 64(sp)
    slt t4, t5, s11
    sd t4, 88(sp)
    ld t6, 88(sp)
    sltu t4, s2, t6
    sd t4, 96(sp)
    ld t5, 80(sp)
    xor t4, t5, s2
    sd t4, 104(sp)
    ld t5, 104(sp)
    seqz t4, t5
    sd t4, 104(sp)
    ld t5, 96(sp)
    ld t6, 104(sp)
    and t4, t5, t6
    sd t4, 112(sp)
    ld t5, 112(sp)
    beqz t5, .Lfoo_3
    mv a0, s8
    ld t5, 64(sp)
    mv a1, t5
    call format
    mv t4, a0
    sd t4, 120(sp)
    ld t5, 120(sp)
    mv t4, t5
    sd t4, 128(sp)
    mv a0, s9
    ld t5, 128(sp)
    mv a1, t5
    call hashmap_delete
    mv t1, a0
    ld t5, 64(sp)
    addw t3, t5, s4
    mv t0, s9
    ld t5, 72(sp)
    mv t2, t5
    mv s9, t0
    mv t4, t3
    sd t4, 64(sp)
    mv t4, t2
    sd t4, 72(sp)
    mv t4, s2
    sd t4, 80(sp)
    j .Lfoo_2
.Lfoo_3:
    li s9, 1500
    li t4, 1600
    sd t4, 136(sp)
    mv t4, s5
    sd t4, 144(sp)
    mv t4, s9
    sd t4, 152(sp)
    mv t4, s3
    sd t4, 160(sp)
    mv t4, s2
    sd t4, 168(sp)
.Lfoo_4:
    ld t5, 152(sp)
    ld t6, 136(sp)
    slt t4, t5, t6
    sd t4, 176(sp)
    ld t6, 176(sp)
    sltu t4, s2, t6
    sd t4, 184(sp)
    ld t5, 168(sp)
    xor t4, t5, s2
    sd t4, 192(sp)
    ld t5, 192(sp)
    seqz t4, t5
    sd t4, 192(sp)
    ld t5, 184(sp)
    ld t6, 192(sp)
    and t4, t5, t6
    sd t4, 200(sp)
    ld t5, 200(sp)
    beqz t5, .Lfoo_5
    mv a0, s8
    ld t5, 152(sp)
    mv a1, t5
    call format
    mv t4, a0
    sd t4, 208(sp)
    ld t5, 208(sp)
    mv t4, t5
    sd t4, 216(sp)
    ld t5, 152(sp)
    mv t4, t5
    sd t4, 224(sp)
    ld t5, 144(sp)
    mv a0, t5
    ld t5, 216(sp)
    mv a1, t5
    ld t5, 224(sp)
    mv a2, t5
    call hashmap_put
    mv t1, a0
    ld t5, 152(sp)
    addw t3, t5, s4
    ld t5, 144(sp)
    mv t0, t5
    ld t5, 160(sp)
    mv t2, t5
    mv t4, t0
    sd t4, 144(sp)
    mv t4, t3
    sd t4, 152(sp)
    mv t4, t2
    sd t4, 160(sp)
    mv t4, s2
    sd t4, 168(sp)
    j .Lfoo_4
.Lfoo_5:
    li t4, 6000
    sd t4, 232(sp)
    li t4, 7000
    sd t4, 240(sp)
    mv t4, s5
    sd t4, 248(sp)
    ld t5, 232(sp)
    mv t4, t5
    sd t4, 256(sp)
    mv t4, s3
    sd t4, 264(sp)
    mv t4, s2
    sd t4, 272(sp)
.Lfoo_6:
    ld t5, 256(sp)
    ld t6, 240(sp)
    slt t4, t5, t6
    sd t4, 280(sp)
    ld t6, 280(sp)
    sltu t4, s2, t6
    sd t4, 288(sp)
    ld t5, 272(sp)
    xor t4, t5, s2
    sd t4, 296(sp)
    ld t5, 296(sp)
    seqz t4, t5
    sd t4, 296(sp)
    ld t5, 288(sp)
    ld t6, 296(sp)
    and t4, t5, t6
    sd t4, 304(sp)
    ld t5, 304(sp)
    beqz t5, .Lfoo_7
    mv a0, s8
    ld t5, 256(sp)
    mv a1, t5
    call format
    mv t4, a0
    sd t4, 312(sp)
    ld t5, 312(sp)
    mv t4, t5
    sd t4, 320(sp)
    ld t5, 256(sp)
    mv t4, t5
    sd t4, 328(sp)
    ld t5, 248(sp)
    mv a0, t5
    ld t5, 320(sp)
    mv a1, t5
    ld t5, 328(sp)
    mv a2, t5
    call hashmap_put
    mv t3, a0
    ld t5, 256(sp)
    addw t0, t5, s4
    ld t5, 248(sp)
    mv t2, t5
    ld t5, 264(sp)
    mv t1, t5
    mv t4, t2
    sd t4, 248(sp)
    mv t4, t0
    sd t4, 256(sp)
    mv t4, t1
    sd t4, 264(sp)
    mv t4, s2
    sd t4, 272(sp)
    j .Lfoo_6
.Lfoo_7:
    la t4, .Lstr35
    sd t4, 336(sp)
    la t4, .Lstr31
    sd t4, 344(sp)
    mv t4, s5
    sd t4, 352(sp)
    mv t4, s6
    sd t4, 360(sp)
    mv s6, s3
    mv t4, s2
    sd t4, 368(sp)
.Lfoo_8:
    ld t5, 360(sp)
    slt t4, t5, s10
    sd t4, 376(sp)
    ld t6, 376(sp)
    sltu t4, s2, t6
    sd t4, 384(sp)
    ld t5, 368(sp)
    xor t4, t5, s2
    sd t4, 392(sp)
    ld t5, 392(sp)
    seqz t4, t5
    sd t4, 392(sp)
    ld t5, 384(sp)
    ld t6, 392(sp)
    and t4, t5, t6
    sd t4, 400(sp)
    ld t5, 400(sp)
    beqz t5, .Lfoo_9
    mv a0, s8
    ld t5, 360(sp)
    mv a1, t5
    call format
    mv t4, a0
    sd t4, 408(sp)
    ld t5, 408(sp)
    mv t4, t5
    sd t4, 416(sp)
    ld t5, 352(sp)
    mv a0, t5
    ld t5, 416(sp)
    mv a1, t5
    call hashmap_get
    mv t4, a0
    sd t4, 424(sp)
    ld t5, 424(sp)
    mv t4, t5
    sd t4, 432(sp)
    ld t5, 360(sp)
    mv t4, t5
    sd t4, 440(sp)
    ld t5, 432(sp)
    ld t6, 440(sp)
    xor t4, t5, t6
    sd t4, 448(sp)
    ld t5, 448(sp)
    seqz t4, t5
    sd t4, 448(sp)
    ld t6, 448(sp)
    sltu t4, s2, t6
    sd t4, 456(sp)
    ld t5, 456(sp)
    beqz t5, .Lfoo_10
    j .Lfoo_11
.Lfoo_10:
    li t4, 170
    sd t4, 464(sp)
    ld t5, 336(sp)
    mv a0, t5
    ld t5, 344(sp)
    mv a1, t5
    ld t5, 464(sp)
    mv a2, t5
    mv a3, s6
    call __assert_fail
    mv t0, a0
.Lfoo_11:
    ld t5, 360(sp)
    addw t2, t5, s4
    ld t5, 352(sp)
    mv t1, t5
    mv t3, s6
    mv t4, t1
    sd t4, 352(sp)
    mv t4, t2
    sd t4, 360(sp)
    mv s6, t3
    mv t4, s2
    sd t4, 368(sp)
    j .Lfoo_8
.Lfoo_9:
    la s6, .Lstr36
    li t4, 0
    sd t4, 472(sp)
    la t4, .Lstr37
    sd t4, 480(sp)
    mv t4, s5
    sd t4, 488(sp)
    mv t4, s10
    sd t4, 496(sp)
    mv s10, s3
    mv t4, s2
    sd t4, 504(sp)
.Lfoo_12:
    ld t5, 496(sp)
    slt t4, t5, s9
    sd t4, 512(sp)
    ld t6, 512(sp)
    sltu t4, s2, t6
    sd t4, 520(sp)
    ld t5, 504(sp)
    xor t4, t5, s2
    sd t4, 528(sp)
    ld t5, 528(sp)
    seqz t4, t5
    sd t4, 528(sp)
    ld t5, 520(sp)
    ld t6, 528(sp)
    and t4, t5, t6
    sd t4, 536(sp)
    ld t5, 536(sp)
    beqz t5, .Lfoo_13
    ld t5, 488(sp)
    mv a0, t5
    mv a1, s6
    call hashmap_get
    mv t4, a0
    sd t4, 544(sp)
    ld t5, 544(sp)
    mv t4, t5
    sd t4, 552(sp)
    ld t5, 552(sp)
    ld t6, 472(sp)
    xor t4, t5, t6
    sd t4, 560(sp)
    ld t5, 560(sp)
    seqz t4, t5
    sd t4, 560(sp)
    ld t6, 560(sp)
    sltu t4, s2, t6
    sd t4, 568(sp)
    ld t5, 568(sp)
    beqz t5, .Lfoo_14
    j .Lfoo_15
.Lfoo_14:
    li t4, 172
    sd t4, 576(sp)
    ld t5, 480(sp)
    mv a0, t5
    ld t5, 344(sp)
    mv a1, t5
    ld t5, 576(sp)
    mv a2, t5
    mv a3, s10
    call __assert_fail
    mv t0, a0
.Lfoo_15:
    ld t5, 496(sp)
    addw t2, t5, s4
    ld t5, 488(sp)
    mv t1, t5
    mv t3, s10
    mv t4, t1
    sd t4, 488(sp)
    mv t4, t2
    sd t4, 496(sp)
    mv s10, t3
    mv t4, s2
    sd t4, 504(sp)
    j .Lfoo_12
.Lfoo_13:
    mv s10, s5
    mv t4, s9
    sd t4, 584(sp)
    mv s9, s3
    mv t4, s2
    sd t4, 592(sp)
.Lfoo_16:
    ld t5, 584(sp)
    ld t6, 136(sp)
    slt t4, t5, t6
    sd t4, 600(sp)
    ld t6, 600(sp)
    sltu t4, s2, t6
    sd t4, 608(sp)
    ld t5, 592(sp)
    xor t4, t5, s2
    sd t4, 616(sp)
    ld t5, 616(sp)
    seqz t4, t5
    sd t4, 616(sp)
    ld t5, 608(sp)
    ld t6, 616(sp)
    and t4, t5, t6
    sd t4, 624(sp)
    ld t5, 624(sp)
    beqz t5, .Lfoo_17
    mv a0, s8
    ld t5, 584(sp)
    mv a1, t5
    call format
    mv t4, a0
    sd t4, 632(sp)
    ld t5, 632(sp)
    mv t4, t5
    sd t4, 640(sp)
    mv a0, s10
    ld t5, 640(sp)
    mv a1, t5
    call hashmap_get
    mv t4, a0
    sd t4, 648(sp)
    ld t5, 648(sp)
    mv t4, t5
    sd t4, 656(sp)
    ld t5, 584(sp)
    mv t4, t5
    sd t4, 664(sp)
    ld t5, 656(sp)
    ld t6, 664(sp)
    xor t4, t5, t6
    sd t4, 672(sp)
    ld t5, 672(sp)
    seqz t4, t5
    sd t4, 672(sp)
    ld t6, 672(sp)
    sltu t4, s2, t6
    sd t4, 680(sp)
    ld t5, 680(sp)
    beqz t5, .Lfoo_18
    j .Lfoo_19
.Lfoo_18:
    li t4, 174
    sd t4, 688(sp)
    ld t5, 336(sp)
    mv a0, t5
    ld t5, 344(sp)
    mv a1, t5
    ld t5, 688(sp)
    mv a2, t5
    mv a3, s9
    call __assert_fail
    mv t0, a0
.Lfoo_19:
    ld t5, 584(sp)
    addw t2, t5, s4
    mv t1, s10
    mv t3, s9
    mv s10, t1
    mv t4, t2
    sd t4, 584(sp)
    mv s9, t3
    mv t4, s2
    sd t4, 592(sp)
    j .Lfoo_16
.Lfoo_17:
    mv s9, s5
    ld t5, 136(sp)
    mv s10, t5
    mv t4, s3
    sd t4, 696(sp)
    mv t4, s2
    sd t4, 704(sp)
.Lfoo_20:
    slt t4, s10, s11
    sd t4, 712(sp)
    ld t6, 712(sp)
    sltu t4, s2, t6
    sd t4, 720(sp)
    ld t5, 704(sp)
    xor t4, t5, s2
    sd t4, 728(sp)
    ld t5, 728(sp)
    seqz t4, t5
    sd t4, 728(sp)
    ld t5, 720(sp)
    ld t6, 728(sp)
    and t4, t5, t6
    sd t4, 736(sp)
    ld t5, 736(sp)
    beqz t5, .Lfoo_21
    mv a0, s9
    mv a1, s6
    call hashmap_get
    mv t4, a0
    sd t4, 744(sp)
    ld t5, 744(sp)
    mv t4, t5
    sd t4, 752(sp)
    ld t5, 752(sp)
    ld t6, 472(sp)
    xor t4, t5, t6
    sd t4, 760(sp)
    ld t5, 760(sp)
    seqz t4, t5
    sd t4, 760(sp)
    ld t6, 760(sp)
    sltu t4, s2, t6
    sd t4, 768(sp)
    ld t5, 768(sp)
    beqz t5, .Lfoo_22
    j .Lfoo_23
.Lfoo_22:
    li t4, 176
    sd t4, 776(sp)
    ld t5, 480(sp)
    mv a0, t5
    ld t5, 344(sp)
    mv a1, t5
    ld t5, 776(sp)
    mv a2, t5
    ld t5, 696(sp)
    mv a3, t5
    call __assert_fail
    mv t0, a0
.Lfoo_23:
    addw t2, s10, s4
    mv t1, s9
    ld t5, 696(sp)
    mv t3, t5
    mv s9, t1
    mv s10, t2
    mv t4, t3
    sd t4, 696(sp)
    mv t4, s2
    sd t4, 704(sp)
    j .Lfoo_20
.Lfoo_21:
    mv s10, s5
    mv s9, s11
    mv s11, s3
    mv t4, s2
    sd t4, 784(sp)
.Lfoo_24:
    slt t4, s9, s7
    sd t4, 792(sp)
    ld t6, 792(sp)
    sltu t4, s2, t6
    sd t4, 800(sp)
    ld t5, 784(sp)
    xor t4, t5, s2
    sd t4, 808(sp)
    ld t5, 808(sp)
    seqz t4, t5
    sd t4, 808(sp)
    ld t5, 800(sp)
    ld t6, 808(sp)
    and t4, t5, t6
    sd t4, 816(sp)
    ld t5, 816(sp)
    beqz t5, .Lfoo_25
    mv a0, s8
    mv a1, s9
    call format
    mv t4, a0
    sd t4, 824(sp)
    ld t5, 824(sp)
    mv t4, t5
    sd t4, 832(sp)
    mv a0, s10
    ld t5, 832(sp)
    mv a1, t5
    call hashmap_get
    mv t4, a0
    sd t4, 840(sp)
    ld t5, 840(sp)
    mv t4, t5
    sd t4, 848(sp)
    mv t4, s9
    sd t4, 856(sp)
    ld t5, 848(sp)
    ld t6, 856(sp)
    xor t4, t5, t6
    sd t4, 864(sp)
    ld t5, 864(sp)
    seqz t4, t5
    sd t4, 864(sp)
    ld t6, 864(sp)
    sltu t4, s2, t6
    sd t4, 872(sp)
    ld t5, 872(sp)
    beqz t5, .Lfoo_26
    j .Lfoo_27
.Lfoo_26:
    li t4, 178
    sd t4, 880(sp)
    ld t5, 336(sp)
    mv a0, t5
    ld t5, 344(sp)
    mv a1, t5
    ld t5, 880(sp)
    mv a2, t5
    mv a3, s11
    call __assert_fail
    mv t0, a0
.Lfoo_27:
    addw t2, s9, s4
    mv t1, s10
    mv t3, s11
    mv s10, t1
    mv s9, t2
    mv s11, t3
    mv t4, s2
    sd t4, 784(sp)
    j .Lfoo_24
.Lfoo_25:
    mv s10, s5
    mv s11, s7
    mv s7, s3
    mv s9, s2
.Lfoo_28:
    ld t6, 232(sp)
    slt t4, s11, t6
    sd t4, 888(sp)
    ld t6, 888(sp)
    sltu t4, s2, t6
    sd t4, 896(sp)
    xor t4, s9, s2
    sd t4, 904(sp)
    ld t5, 904(sp)
    seqz t4, t5
    sd t4, 904(sp)
    ld t5, 896(sp)
    ld t6, 904(sp)
    and t4, t5, t6
    sd t4, 912(sp)
    ld t5, 912(sp)
    beqz t5, .Lfoo_29
    mv a0, s10
    mv a1, s6
    call hashmap_get
    mv t4, a0
    sd t4, 920(sp)
    ld t5, 920(sp)
    mv t4, t5
    sd t4, 928(sp)
    ld t5, 928(sp)
    ld t6, 472(sp)
    xor t4, t5, t6
    sd t4, 936(sp)
    ld t5, 936(sp)
    seqz t4, t5
    sd t4, 936(sp)
    ld t6, 936(sp)
    sltu t4, s2, t6
    sd t4, 944(sp)
    ld t5, 944(sp)
    beqz t5, .Lfoo_30
    j .Lfoo_31
.Lfoo_30:
    li t4, 180
    sd t4, 952(sp)
    ld t5, 480(sp)
    mv a0, t5
    ld t5, 344(sp)
    mv a1, t5
    ld t5, 952(sp)
    mv a2, t5
    mv a3, s7
    call __assert_fail
    mv t0, a0
.Lfoo_31:
    addw t2, s11, s4
    mv t1, s10
    mv t3, s7
    mv s10, t1
    mv s11, t2
    mv s7, t3
    mv s9, s2
    j .Lfoo_28
.Lfoo_29:
    mv s10, s5
    ld t5, 232(sp)
    mv s7, t5
    mv s9, s3
    mv s11, s2
.Lfoo_32:
    ld t6, 240(sp)
    slt t4, s7, t6
    sd t4, 960(sp)
    ld t6, 960(sp)
    sltu t4, s2, t6
    sd t4, 968(sp)
    xor t4, s11, s2
    sd t4, 976(sp)
    ld t5, 976(sp)
    seqz t4, t5
    sd t4, 976(sp)
    ld t5, 968(sp)
    ld t6, 976(sp)
    and t4, t5, t6
    sd t4, 984(sp)
    ld t5, 984(sp)
    beqz t5, .Lfoo_33
    mv a0, s8
    mv a1, s7
    call format
    mv t4, a0
    sd t4, 992(sp)
    ld t5, 992(sp)
    mv t4, t5
    sd t4, 1000(sp)
    mv t4, s7
    sd t4, 1008(sp)
    mv a0, s10
    ld t5, 1000(sp)
    mv a1, t5
    ld t5, 1008(sp)
    mv a2, t5
    call hashmap_put
    mv t0, a0
    addw t2, s7, s4
    mv t1, s10
    mv t3, s9
    mv s10, t1
    mv s7, t2
    mv s9, t3
    mv s11, s2
    j .Lfoo_32
.Lfoo_33:
    mv a0, s5
    mv a1, s6
    call hashmap_get
    mv s5, a0
    mv s6, s5
    ld t6, 472(sp)
    xor s5, s6, t6
    seqz s5, s5
    sltu s6, s2, s5
    beqz s6, .Lfoo_34
    j .Lfoo_35
.Lfoo_34:
    li s5, 184
    ld t5, 480(sp)
    mv a0, t5
    ld t5, 344(sp)
    mv a1, t5
    mv a2, s5
    mv a3, s3
    call __assert_fail
    mv s5, a0
.Lfoo_35:
    la s5, .Lstr38
    mv a0, s5
    call printf
    mv s5, a0
    li s5, 1
    mv a0, s5
    ld ra, 1096(sp)
    ld s2, 1016(sp)
    ld s3, 1024(sp)
    ld s4, 1032(sp)
    ld s5, 1040(sp)
    ld s6, 1048(sp)
    ld s7, 1056(sp)
    ld s8, 1064(sp)
    ld s9, 1072(sp)
    ld s10, 1080(sp)
    ld s11, 1088(sp)
    addi sp, sp, 1120
    ret
.size foo, .-foo
.data
.type .Lstr29, @object
.align 0
.Lstr29:
    .byte 10
    .byte 0
.size .Lstr29, 2
.data
.type .Lstr30, @object
.align 0
.Lstr30:
    .byte 99
    .byte 97
    .byte 112
    .byte 32
    .byte 62
    .byte 32
    .byte 48
    .byte 0
.size .Lstr30, 8
.data
.type .Lstr31, @object
.align 0
.Lstr31:
    .byte 47
    .byte 104
    .byte 111
    .byte 109
    .byte 101
    .byte 47
    .byte 100
    .byte 97
    .byte 118
    .byte 105
    .byte 100
    .byte 47
    .byte 67
    .byte 111
    .byte 100
    .byte 101
    .byte 47
    .byte 122
    .byte 111
    .byte 98
    .byte 47
    .byte 116
    .byte 101
    .byte 115
    .byte 116
    .byte 115
    .byte 47
    .byte 104
    .byte 97
    .byte 115
    .byte 104
    .byte 109
    .byte 97
    .byte 112
    .byte 46
    .byte 99
    .byte 0
.size .Lstr31, 37
.data
.type .Lstr32, @object
.align 0
.Lstr32:
    .byte 109
    .byte 97
    .byte 112
    .byte 50
    .byte 46
    .byte 117
    .byte 115
    .byte 101
    .byte 100
    .byte 32
    .byte 61
    .byte 61
    .byte 32
    .byte 110
    .byte 107
    .byte 101
    .byte 121
    .byte 115
    .byte 0
.size .Lstr32, 19
.data
.type .Lstr33, @object
.align 0
.Lstr33:
    .byte 105
    .byte 110
    .byte 116
    .byte 101
    .byte 114
    .byte 110
    .byte 97
    .byte 108
    .byte 32
    .byte 101
    .byte 114
    .byte 114
    .byte 111
    .byte 114
    .byte 32
    .byte 97
    .byte 116
    .byte 32
    .byte 37
    .byte 115
    .byte 58
    .byte 37
    .byte 100
    .byte 0
.size .Lstr33, 24
.data
.type .Lstr34, @object
.align 0
.Lstr34:
    .byte 107
    .byte 101
    .byte 121
    .byte 32
    .byte 37
    .byte 100
    .byte 0
.size .Lstr34, 7
.data
.type .Lstr35, @object
.align 0
.Lstr35:
    .byte 40
    .byte 115
    .byte 105
    .byte 122
    .byte 101
    .byte 95
    .byte 116
    .byte 41
    .byte 104
    .byte 97
    .byte 115
    .byte 104
    .byte 109
    .byte 97
    .byte 112
    .byte 95
    .byte 103
    .byte 101
    .byte 116
    .byte 40
    .byte 109
    .byte 97
    .byte 112
    .byte 44
    .byte 32
    .byte 102
    .byte 111
    .byte 114
    .byte 109
    .byte 97
    .byte 116
    .byte 40
    .byte 34
    .byte 107
    .byte 101
    .byte 121
    .byte 32
    .byte 37
    .byte 100
    .byte 34
    .byte 44
    .byte 32
    .byte 105
    .byte 41
    .byte 41
    .byte 32
    .byte 61
    .byte 61
    .byte 32
    .byte 105
    .byte 0
.size .Lstr35, 51
.data
.type .Lstr36, @object
.align 0
.Lstr36:
    .byte 110
    .byte 111
    .byte 32
    .byte 115
    .byte 117
    .byte 99
    .byte 104
    .byte 32
    .byte 107
    .byte 101
    .byte 121
    .byte 0
.size .Lstr36, 12
.data
.type .Lstr37, @object
.align 0
.Lstr37:
    .byte 104
    .byte 97
    .byte 115
    .byte 104
    .byte 109
    .byte 97
    .byte 112
    .byte 95
    .byte 103
    .byte 101
    .byte 116
    .byte 40
    .byte 109
    .byte 97
    .byte 112
    .byte 44
    .byte 32
    .byte 34
    .byte 110
    .byte 111
    .byte 32
    .byte 115
    .byte 117
    .byte 99
    .byte 104
    .byte 32
    .byte 107
    .byte 101
    .byte 121
    .byte 34
    .byte 41
    .byte 32
    .byte 61
    .byte 61
    .byte 32
    .byte 78
    .byte 85
    .byte 76
    .byte 76
    .byte 0
.size .Lstr37, 40
.data
.type .Lstr38, @object
.align 0
.Lstr38:
    .byte 79
    .byte 75
    .byte 10
    .byte 0
.size .Lstr38, 4
