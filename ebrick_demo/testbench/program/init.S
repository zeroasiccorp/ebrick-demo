# Copyright (c) 2024 Zero ASIC Corporation
# This code is licensed under Apache License 2.0 (see LICENSE for details)

# ref: https://wiki.osdev.org/RISC-V_Bare_Bones

#include "ebrick_memory_map.h"

.section .text.init

.global _start
_start:
# set the stack pointer
    la sp, __stack_top

# call the main function
    call main

# tell simulation to exit by writing a value
# to EXIT_ADDR.  the value written is the integer
# value returned by main()
end:
    li t0, EXIT_ADDR
    sw a0, 0(t0)

# then loop forever
endloop:
    j endloop
