#!/usr/bin/env python3

# Copyright (c) 2024 Zero ASIC Corporation
# This code is licensed under Apache License 2.0 (see LICENSE for details)


import os
import umi
import lambdalib
from siliconcompiler import Chip
from siliconcompiler.targets import asap7_demo
from siliconcompiler.flows import lintflow


def __add_ebrick_sources(chip):
    # Add the ebrick itself as a package source
    chip.register_package_source(
        'ebrick_demo',
        os.path.abspath(os.path.dirname(__file__)))

    # Add ebrick_core top
    chip.input('rtl/ebrick_core.v', package='ebrick_demo')
    chip.add('option', 'idir', 'config', package='ebrick_demo')

    # Import umi and lambdalib libraries
    chip.use(umi)
    chip.use(lambdalib)

    # Set the libraries ebrick_core depends on
    chip.add('option', 'library', 'lumi')
    chip.add('option', 'library', 'umi')

    chip.add('option', 'library', 'lambdalib_stdlib')
    chip.add('option', 'library', 'lambdalib_ramlib')
    chip.add('option', 'library', 'lambdalib_vectorlib')

    # Set the top module to ebrick_core
    chip.set('option', 'entrypoint', 'ebrick_core')


def setup_core_design(chip):
    __add_ebrick_sources(chip)

    # Add picorv32 data source
    chip.register_package_source(
        name='picorv32',
        path='git+https://github.com/YosysHQ/picorv32.git',
        ref='a7b56fc81ff1363d20fd0fb606752458cd810552')

    # Add your core files here
    chip.input('picorv32.v', package='picorv32')

    # Add your library imports here


def __setup_asicflow(chip):
    # Setup asic flow

    if chip.get('option', 'mode') == 'asic':
        # set SYNTHESIS macro if running in asic mode
        chip.add('option', 'define', 'SYNTHESIS')

    # Set mode to asic
    chip.set('option', 'mode', 'asic')

    # Add timing constraints
    mainlib = chip.get('asic', 'logiclib')[0]  # This is set by the target
    chip.input(f'implementation/{mainlib}.sdc', package='ebrick_demo')

    # Setup physical constraints
    chip.set('constraint', 'density', 40)

    # Provide tool specific settings
    chip.set('tool', 'openroad', 'task', 'place', 'var',
             'gpl_uniform_placement_adjustment',
             '0.2')

    pdk = chip.get('option', 'pdk')
    if pdk == 'asap7':
        # Change pin placement settings to allow for multiple layers
        # to avoid pin placement congestion
        stackup = chip.get('option', 'stackup')
        chip.set('pdk', pdk, 'var', 'openroad', 'pin_layer_vertical', stackup, [
            'M3',
            'M5'
        ])
        chip.set('pdk', pdk, 'var', 'openroad', 'pin_layer_horizontal', stackup, [
            'M4',
            'M6'
        ])
        # Change minimum pin placement distance to 3 tracks for tasks
        # which impact pin placement to reduce routing congestion
        for task in ('floorplan', 'place'):
            chip.add('tool', 'openroad', 'task', task, 'var', 'ppl_arguments', [
                '-min_distance_in_tracks',
                '-min_distance', '3'])
    elif pdk == 'skywater130':
        # Change pin placement settings to allow for multiple layers
        # to avoid pin placement congestion
        stackup = chip.get('option', 'stackup')
        chip.set('pdk', pdk, 'var', 'openroad', 'pin_layer_vertical', stackup, [
            'met2',
            'met4'
        ])
        chip.set('pdk', pdk, 'var', 'openroad', 'pin_layer_horizontal', stackup, [
            'met1',
            'met3'
        ])


def __setup_lintflow(chip):
    # Change job name to avoid overwriting asicflow
    chip.set('option', 'jobname',
             f'{chip.get("option", "jobname")}_lint')

    # Import lintflow
    chip.use(lintflow)

    # Set mode to simulation
    chip.set('option', 'mode', 'sim')

    # Add tool specific settings
    chip.add('tool', 'verilator', 'task', 'lint', 'option', '-Wall')
    chip.add('tool', 'verilator', 'task', 'lint', 'file', 'config',
             'config/config.vlt', package='ebrick_demo')


def __setup_testbench(chip):
    # Remove the entrypoint setting as this will need to be the testbench
    chip.unset('option', 'entrypoint')

    # Add tool specific settings
    chip.set('tool', 'verilator', 'task', 'compile', 'file', 'config',
             'config/config.vlt', package='ebrick_demo')


def setup(chip, testbench=False):
    # Add source files for this design
    setup_core_design(chip)

    if not testbench:
        flow = chip.get('option', 'flow')
        if flow == 'asicflow':
            __setup_asicflow(chip)
        elif flow == 'lintflow':
            __setup_lintflow(chip)
        else:
            raise ValueError(f'{flow} is not recognized')
    else:
        __setup_testbench(chip)

    return chip


def main():
    chip = Chip("ebrick-demo")

    # needed because the test imports ebrick
    from ebrick_demo.testbench.test_prv32 import run_test as run_test_prv32
    from ebrick_demo.testbench.test_prv32_memagent import run_test as run_test_prv32_memagent

    run_test_map = {
        'test_prv32': run_test_prv32,
        'test_prv32_memagent': run_test_prv32_memagent
    }

    args = chip.create_cmdline(
        switchlist=['-target',
                    '-flow',
                    '-resume',
                    '-jobname',
                    '-quiet',
                    '-remote'],
        additional_args={
            '-test': {
                'type': str,
                'nargs': '?',
                'const': 'test_prv32',
                'choices': list(run_test_map.keys()),
                'help': 'run a test, defaulting to test_prv32',
                'sc_print': False
            },
            '-trace': {
                'action': 'store_true',
                'help': "dump waveforms during simulation",
                'sc_print': False
            },
            '-fast': {
                'action': 'store_true',
                'help': "don't build the simulator if one is found",
                'sc_print': False
            }
        }
    )

    if args['test']:
        run_test_map[args['test']](
            trace=args['trace'],
            fast=args['fast']
        )
        return

    ################################
    # Lintflow is the default flow
    chip.set('option', 'flow', 'lintflow', clobber=False)

    if not chip.get('option', 'target'):
        # load the target if it wasn't specified at the CLI
        chip.load_target(asap7_demo)

    # Setup chip
    setup(chip)

    chip.run()
    chip.summary()


if __name__ == "__main__":
    main()
