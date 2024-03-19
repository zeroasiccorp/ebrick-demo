#!/usr/bin/env python3

# Example showing how to simulate an EBRICK using switchboard.  External
# memory is implemented with the umi_mem_agent Verilog module.

# We suggest that you read through the test_prv32.py script first
# before diving into this example.

# Copyright (c) 2024 Zero ASIC Corporation
# This code is licensed under Apache License 2.0 (see LICENSE for details)

import sys
import numpy as np

import ebrick_demo.ebrick as ebrick
from ebrick_demo.testbench.program.riscv import build_riscv_binary

from pathlib import Path
from switchboard import SbDut, UmiTxRx, PyUmiPacket, UmiCmd, umi_opcode

from siliconcompiler.package import path as sc_path


def run_test(trace=False, fast=False):
    # build the simulation
    print('*** Setting up simulation build ***')

    dut = SbDut('testbench', tool='verilator', default_main=True, trace=trace)

    ebrick.setup(dut, testbench=True)

    dut.add('option', 'idir', 'testbench', package='ebrick_demo')
    dut.input('testbench/ebrick_crossbar_4x4.sv', package='ebrick_demo')
    dut.input('testbench/testbench_prv32_memagent.sv', package='ebrick_demo')

    # build the program binary
    print('*** Building program binary ***')

    build_riscv_binary(
        files=['program/hello.c', 'program/init.S'],
        linkcfg='program/link.ld',
        incdirs=['.', '../config'],
        output='program/hello.bin',
        cwd=Path(sc_path(dut, 'ebrick_demo')) / 'testbench'
    )

    # building the simulator binary
    print('*** Building program binary ***')

    dut.build(fast=fast)

    # create queues
    print('*** Creating switchboard queues ***')

    mem = UmiTxRx('host2mem_0.q', 'mem2host_0.q', fresh=True, max_bytes=4)
    mon = UmiTxRx('mtr2core_0.q', 'core2mtr_0.q', fresh=True)
    gpioq = UmiTxRx('host2gpio_0.q', 'gpio2host_0.q', fresh=True)

    # launch the simulation
    print('*** Launching RTL simulation ***')

    dut.simulate()

    # put DUT into reset
    print('*** Assert ebrick "nreset" ***')

    gpio = gpioq.gpio(owidth=32, iwidth=32, init=0)

    # de-assert nreset
    print('*** De-assert ebrick "nreset" ***')

    gpio.o[0] = 1  # de-assert nreset

    # program the memory
    print('*** Programming RAM ***')

    program_file = Path(sc_path(dut, 'ebrick_demo')) / 'testbench' / 'program' / 'hello.bin'
    program = np.fromfile(program_file, dtype=np.uint8)
    # 0x8888 is the chipid for the Python host
    # Please refer to ebrick_memory_map.vh(or .h) in the config directory
    mem.write(0x0, program, srcaddr=0x8888 << 40)

    # assert go
    print('*** Assert ebrick "go" ***')

    gpio.o[1] = 1  # assert go

    # print characters received
    print('*** Monitoring ebrick output ***')

    while True:
        p = mon.recv(blocking=False)
        if p is not None:
            # make sure that we know how to process this request
            opcode = umi_opcode(p.cmd)
            assert opcode in {UmiCmd.UMI_REQ_WRITE, UmiCmd.UMI_REQ_POSTED}, \
                f'Unsupported opcode: {opcode}'

            # send a write reponse if this was an ordinary write (non-posted)
            if opcode == UmiCmd.UMI_REQ_WRITE:
                # change the command to a write response
                cmd = (p.cmd & 0xffffffe0) | int(UmiCmd.UMI_RESP_WRITE)

                # flip the source address and destination address
                resp = PyUmiPacket(cmd, p.srcaddr, p.dstaddr)

                # send the response
                mon.send(resp)

            # 0xCCCC is the chipid for the Python monitor
            # 0x00_C000_0000 is the write address for the UART device
            # Please refer to ebrick_memory_map.vh(or .h) in the config directory
            if p.dstaddr == ((0x00 << 56) + (0xCCCC << 40) + 0x00C0000000):
                # print the character received
                c = chr(p.data[0])
                print(c, end='', flush=True)
            # 0xCCCC is the chipid for the Python monitor
            # 0x00_D000_0000 is the EXIT ADDRESS
            # Please refer to ebrick_memory_map.vh(or .h) in the config directory
            elif p.dstaddr == ((0x00 << 56) + (0xCCCC << 40) + 0x00D0000000):
                # exit the simulation
                exit_code = int(p.data.view(np.uint32)[0])
                sys.exit(exit_code)
            else:
                raise ValueError(f'Unsupported address: 0x{p.dstaddr:08x}')


if __name__ == '__main__':
    from argparse import ArgumentParser

    parser = ArgumentParser()
    parser.add_argument('--fast', action='store_true',
        help="don't build the simulator if one is found")
    parser.add_argument('--trace', action='store_true',
        help="dump waveforms during simulation")

    args = parser.parse_args()

    run_test(trace=args.trace, fast=args.fast)
