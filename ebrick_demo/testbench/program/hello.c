// Copyright (c) 2024 Zero ASIC Corporation
// This code is licensed under Apache License 2.0 (see LICENSE for details)

// Simple RISC-V program that prints a message and exits

#include "ebrick_memory_map.h"

static inline void puts(char* str) {
	// in this example, the "UART" is simply a memory address where
	// characters are written. each character is transmitted in a
	// UMI packet that is received by the Python stimulus code

	char* s = str;
	char c;
	while ((c = *s++)) {
		*((volatile int*)UART_ADDR) = c;
	}
	*((volatile int*)UART_ADDR) = '\n';
}

int main() {
	// print a message
    puts("Hello World!");

	// return zero, indicating a successful run
    return 0;
}
