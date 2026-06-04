.text
.globl foo
.type foo, @function
foo:
    addi sp, sp, -16
    addi t0, sp, 0
    li t1, 42
    sw t1, 0(t0)
    mv a0, t1
    addi sp, sp, 16
    ret
.size foo, .-foo
