/******************************************************************************
 * Copyright 2024 Zero ASIC Corporation
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * ----
 *
 * Documentation:
 *  This file defines the Address Map for the PicoRV32 demo
 *  The demo consists of 4 components:
 *      1. The main memory
 *      2. The ebrick core consisting of picorv32 and an axilite to UMI converter
 *      3. A UMITxRx based host that allows memory access from the Python test
 *      4. A UMITxRx based device that allows UART access and indicates program end
 *
 *  The Address Map follows the UMI standard where each component is assigned
 *  a 16 bit chip ID:
 *      1. The main memory  (0x0000)
 *      2. The ebrick core  (0x4444)
 *      3. UMITxRx host     (0x8888)
 *      4. UMITxRx device   (0xCCCC)
 *
 *  These IDs are arbitrarily selected with uniqueness being the only criteria.
 *  The address format is as follows:
 *   -------- ---------------- ----------------------------------------
 *  |Reserved|    chip ID     |    component (ebrick) address space    |
 *   -------- ---------------- ----------------------------------------
 *  | 8 bits |    16 bits     |                 40 bits                |
 *   -------- ---------------- ----------------------------------------
 *
 *  NOTE: This file should not be changed independently
 *  Please also make equivalent changes in ebrick_memory_map.vh
 *
 ****************************************************************************/
#ifndef __EBRICK_MEM_MAP_H__
#define __EBRICK_MEM_MAP_H__

// Memory Size is 32768 kiB
// A 40 bit wide zero is ORed to limit the bit width of the macro
#define MAIN_MEMORY_SIZE  0x0000000000 | (1 << 15)

#define MEM_CHIPID        0x0000
#define MEM_ADDR_LOW      ((0x00 << 56) + (MEM_CHIPID << 40) + 0x0000000000)
#define MEM_ADDR_HIGH     ((0x00 << 56) + (MEM_CHIPID << 40) + (MAIN_MEMORY_SIZE-1))

// Address range for the ebrick core
#define CORE_CHIPID       0x4444
#define CORE_ADDR_LOW     ((0x00 << 56) + (CORE_CHIPID << 40) + 0x0000000000)
#define CORE_ADDR_HIGH    ((0x00 << 56) + (CORE_CHIPID << 40) + 0xFFFFFFFFFF)

// Address range for the Python UMI host
#define HOST_CHIPID       0x8888
#define HOST_ADDR_LOW     ((0x00 << 56) + (HOST_CHIPID << 40) + 0x0000000000)
#define HOST_ADDR_HIGH    ((0x00 << 56) + (HOST_CHIPID << 40) + 0xFFFFFFFFFF)

// Only 2 addresses are valid for the Monitor
// UART at      0x00CC_CC00_C000_0000
// Exit Code at 0x00CC_CC00_D000_0000
// While the address range is defined as 1 TB, if a request to
// any address other than UART and Exit Code is issues, the
// Python host will return an error
#define MONITOR_CHIPID    0xCCCC
#define MONITOR_ADDR_LOW  ((0x00 << 56) + (MONITOR_CHIPID << 40) + 0x0000000000)
#define MONITOR_ADDR_HIGH ((0x00 << 56) + (MONITOR_CHIPID << 40) + 0xFFFFFFFFFF)

#define UART_ADDR         0xC0000000
#define EXIT_ADDR         0xD0000000

#endif
