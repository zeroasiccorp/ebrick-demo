#!/usr/bin/env python3

# Example showing how to simulate an EBRICK using switchboard.  External
# memory is implemented in Python.

# Copyright (c) 2024 Zero ASIC Corporation
# This code is licensed under Apache License 2.0 (see LICENSE for details)

import sys
import numpy as np
from pathlib import Path

from siliconcompiler.package import path as sc_path
from switchboard import SbDut, UmiTxRx, PyUmiPacket, UmiCmd, umi_opcode

import ebrick_demo.ebrick as ebrick
from ebrick_demo.testbench.program.riscv import build_riscv_binary
from ebrick_demo.testbench.umi_ram import UmiRam

# size of the processor memory in bytes
MEMORY_SIZE = 32768


def run_test(trace=False, fast=False):
    ############################
    # build the RTL simulation #
    ############################

    print('*** Building the RTL simulation ***')

    # SbDut is a subclass of siliconcompiler.Chip, with some extra
    # options and features geared towards simulation with switchboard.
    #
    # Here's what the constructor arguments mean:
    # * 'testbench' is the name of the top-level module
    # * 'tool' indicates the Verilog simulation tool ('verilator' or 'icarus')
    # * 'trace' indicates whether waveforms should be dumped
    # * 'default_main' is Verilator-specific; means that switchboard's default
    #   C++ main() implementation should be used. In the future, it will not
    #   generally be necessary to specify this, because default_main=True will
    #   become the default in the SbDut constructor.

    dut = SbDut('testbench', tool='verilator', trace=trace, default_main=True)

    # The next few commands specify the Verilog sources to be used in the
    # simulation.  ebrick.setup() configures the RTL sources for the custom
    # EBRICK design (which might be extensive in a complete design).  The
    # add() and input() commands after setup() are for files outside of the
    # EBRICK that are only used for simulation.

    ebrick.setup(dut, testbench=True)

    dut.add('option', 'idir', 'testbench', package='ebrick_demo')
    dut.input('testbench/testbench.sv', package='ebrick_demo')

    # build() kicks off the simulator build using the source files configured
    # in the previous commands. The result depends on the simulator being used
    # For Verilator, the output of build() is an executable that can be run
    # in a standalone fashion, while for Icarus Verilog, the result is a binary
    # run with vvp. The "fast" argument indicates whether the build should be
    # skipped if the binary output already exists.

    dut.build(fast=fast)

    ############################
    # build the program binary #
    ############################

    print('*** Building RISC-V program binary ***')

    # This command compiles C code into a RISC-V binary that can run
    # on the PicoRV32 processor. Other types of custom EBRICKs might
    # have different compilation tools.

    build_riscv_binary(
        files=['program/hello.c', 'program/init.S'],
        linkcfg='program/link.ld',
        incdirs=['.', '../config'],
        output='program/hello.bin',
        cwd=Path(sc_path(dut, 'ebrick_demo')) / 'testbench'
    )

    #############################
    # create switchboard queues #
    #############################

    print('*** Creating switchboard queues ***')

    # These commands create new switchboard queues that will show up
    # as files in the file system. The queue names must match the
    # names used on the Verilog side in testbench.sv. This is somewhat
    # similar to specifying TCP ports to be used on two sides of a
    # connection.
    #
    # The "fresh" argument means that existing queues with the same
    # names are deleted. This is important because switchboard queues
    # are *not* automatically at the end of a simulation. Hence, the
    # standard order of operations is:
    #
    # 1. Create queues with fresh=True
    # 2. Start the simulation
    # 3. Start interacting with the simulation through the queues
    #
    # In the future, fresh=True will become the default.

    mon = UmiTxRx('mtr2core_0.q', 'core2mtr_0.q', fresh=True)
    gpioq = UmiTxRx('host2gpio_0.q', 'gpio2host_0.q', fresh=True)

    #############################
    # launch the RTL simulation #
    #############################

    print('*** Launching RTL simulation ***')

    # simulate() launches the RTL simulation built earlier via the build() command

    dut.simulate()

    #####################
    # main test program #
    #####################

    # put DUT into reset
    print('*** Assert ebrick "nreset" ***')

    # The UmiTxRx.gpio() method creates a UmiGpio object from a generic UMI
    # connection.  The UmiGpio object offers a convenient abstraction over
    # generic UMI read()/write() commands, since it allows bits to be set
    # directly with a Verilog-like slice notation.
    #
    # Each UmiGpio instance corresponds to an instance of umi_gpio in the RTL
    # simulation. In this case, there is one umi_gpio instance in testbench.sv,
    # and it has IWIDTH=32, OWIDTH=32. Those same values are provided to the
    # UmiTxRx.gpio() method, along with the initial value of the GPIO outputs,
    # "init".
    #
    # From testbench.sv, the GPIO mapping is as follows:
    # * Output 0: nreset
    # * Output 1: go
    #
    # Setting init=0 means that nreset=0, go=0. Hence, the EBRICK is initially
    # held in reset.

    gpio = gpioq.gpio(iwidth=32, owidth=32, init=0)

    # de-assert nreset
    print('*** De-assert ebrick "nreset" ***')

    # The notation UmiGpio.o[n] = x means, "set the nth bit of UmiGpio to x"
    # Under the hood, this is implemented with a UMI write transaction to the
    # umi_gpio instance in testbench.sv.
    #
    # Verilog-like slice notation may also be used, e.g. UmiGpio.o[msb:lsb] = x

    gpio.o[0] = 1  # de-assert nreset

    # program the memory
    print('*** Programming RAM ***')

    # np.fromfile() is a standard NumPy function that reads a file into
    # a NumPy array.  Since dtype=np.uint8, the numpy array is formatted
    # as a byte array.

    program_file = Path(sc_path(dut, 'ebrick_demo')) / 'testbench' / 'program' / 'hello.bin'
    program_mem = np.fromfile(program_file, dtype=np.uint8)

    # create a Python model of the processor memory and initialize it
    # with the RISC-V program contents

    main_memory = UmiRam(MEMORY_SIZE)
    main_memory.initialize_memory(0, program_mem)

    # assert go
    print('*** Assert ebrick "go" ***')

    # "go" is a standard signal on the EBRICK interface, intended to signal that
    # configuration is complete, and the EBRICK may boot.  Here, we use the "go"
    # signal to indicate that program memory has been initialized, so the RISC-V
    # processor may start fetching instructions from it.

    gpio.o[1] = 1  # assert go

    # Main loop: we monitor incoming UMI requests from the processor and implement
    # them. Three types of requests are supported:
    #
    # 1. Memory transactions (read/write): these are forwarded to the UmiRam object
    # 2. Character printing: UMI packet contains a character to be written to the screen
    # 3. Exit simulation: Tells the script that the RISC-V program has reached the end,
    #    so the Verilog simulation should exit (otherwise it would keep running)
    #
    # This processing loop is effectively a memory map: program memory resides in one
    # part of the global address space, while character printing and simulation control
    # reside in other parts. The memory map can be adapted for different types of EBRICK
    # designs.
    #
    # The global address space is 64 bits, where bits 55:40 are called the "chipid",
    # while bits 39:0 correspond to addresses within a given chiplet (bits 63:56 are
    # currently reserved). The idea is that each unique "chipid" value corresponds to
    # different chiplet. In this example, we've used the following "chipid" values:
    #
    # * chipid=0x0000: UmiRam
    # * chipid=0xCCCC: character printing and simulation control
    # * chipid=0xDDDD: EBRICK DUT
    #
    # Details of the memory map are contained in ebrick_demo/config/ebrick_memory_map.vh

    print('*** Monitoring ebrick output ***')

    while True:
        # UmiTxRx.recv() returns a PyUmiPacket object.  blocking=False means that
        # the method returns None if there is no UMI packet immediately available.
        p = mon.recv(blocking=False)

        if p is not None:
            # make sure that we know how to process this request
            opcode = umi_opcode(p.cmd)
            assert opcode in {UmiCmd.UMI_REQ_READ, UmiCmd.UMI_REQ_WRITE, UmiCmd.UMI_REQ_POSTED}, \
                f'Unsupported opcode: {opcode}'

            # 0x0000 is the chipid for UmiRam
            # 0x00_0000_0000 to MEMORY_SIZE is address space for main memory
            if p.dstaddr < ((0x0000 << 40) + MEMORY_SIZE):
                if opcode in {UmiCmd.UMI_REQ_WRITE, UmiCmd.UMI_REQ_POSTED}:
                    # commit the write to the Python memory model
                    main_memory.write(p)
                elif opcode == UmiCmd.UMI_REQ_READ:
                    # read the requested data and send it back

                    # change the command to a read response
                    cmd = (p.cmd & 0xffffffe0) | int(UmiCmd.UMI_RESP_READ)

                    # format response into a packet. in UMI, outgoing requests have
                    # a srcaddr field that indicates where the response should be
                    # sent. hence the dstaddr and srcaddr fields are flipped when
                    # formatting the response packet.
                    resp = PyUmiPacket(cmd, p.srcaddr, p.dstaddr, main_memory.read(p))

                    # send the packet back to the processor
                    mon.send(resp)

            # 0xCCCC is the chipid for the Python monitor
            # 0x00_C000_0000 is the write address for the UART device
            elif p.dstaddr == ((0xCCCC << 40) + 0x00C0000000):
                # print the character received
                c = chr(p.data[0])
                print(c, end='', flush=True)

            # 0xCCCC is the chipid for the Python monitor
            # 0x00_D000_0000 is the EXIT ADDRESS
            elif p.dstaddr == ((0xCCCC << 40) + 0x00D0000000):
                # exit the simulation
                exit_code = int(p.data.view(np.uint32)[0])
                sys.exit(exit_code)
            else:
                raise ValueError(f'Unsupported address: 0x{p.dstaddr:08x}')

            # send a write reponse if this was an ordinary write (non-posted)
            if opcode == UmiCmd.UMI_REQ_WRITE:
                # change the command to a write response
                cmd = (p.cmd & 0xffffffe0) | int(UmiCmd.UMI_RESP_WRITE)

                # flip the source address and destination address
                resp = PyUmiPacket(cmd, p.srcaddr, p.dstaddr)

                # send the response
                mon.send(resp)


if __name__ == '__main__':
    from argparse import ArgumentParser

    parser = ArgumentParser()
    parser.add_argument('--fast', action='store_true',
        help="don't build the simulator if one is found")
    parser.add_argument('--trace', action='store_true',
        help="dump waveforms during simulation")

    args = parser.parse_args()

    run_test(trace=args.trace, fast=args.fast)
