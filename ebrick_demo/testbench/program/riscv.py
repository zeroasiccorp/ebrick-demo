# Utilities for building RISC-V binaries

# Copyright (c) 2024 Zero ASIC Corporation
# This code is licensed under Apache License 2.0 (see LICENSE for details)

import subprocess

from pathlib import Path


def build_riscv_binary(files, linkcfg, incdirs, output, prefix='riscv64-unknown-elf-', cwd=None):
    elf = run_riscv_gcc(
        files=files,
        linkcfg=linkcfg,
        incdirs=incdirs,
        output=Path(output).with_suffix('.elf'),
        prefix=prefix,
        cwd=cwd
    )

    bin = run_riscv_objcopy(
        input=elf,
        output=output,
        prefix=prefix,
        cwd=cwd
    )

    return bin


def run_riscv_gcc(files, linkcfg, incdirs, output, prefix, cwd=None):
    cmd = [
        f'{prefix}gcc',
        '-mabi=ilp32',
        '-march=rv32im',
        '-static',
        '-mcmodel=medany',
        '-fvisibility=hidden',
        '-nostdlib',
        '-nostartfiles',
        '-fno-builtin'
    ]

    cmd += [f'-I{incdir}' for incdir in incdirs]

    cmd += [f'-T{linkcfg}']

    cmd += files

    cmd += ['-o', output]

    cmd = [str(elem) for elem in cmd]

    subprocess.run(cmd, cwd=cwd, check=True)

    return output


def run_riscv_objcopy(input, output, prefix, cwd=None):
    cmd = [
        f'{prefix}objcopy',
        '-O', 'binary',
        input,
        output
    ]

    cmd = [str(elem) for elem in cmd]

    subprocess.run(cmd, cwd=cwd, check=True)

    return output
