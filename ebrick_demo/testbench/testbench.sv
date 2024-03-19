// Instantiates ebrick_core and connects its UMI ports to switchboard modules
// so that the EBRICK design can be driven from Python. This testbench is
// general-purpose and should be reusable for other types of EBRICK designs.

// Copyright (c) 2024 Zero ASIC Corporation
// This code is licensed under Apache License 2.0 (see LICENSE for details)

`default_nettype none

`include "ebrick_memory_map.vh"
`include "umi_macros.vh"

module testbench (
    // clocks work differently in Verilator vs. other simulators. when
    // using Verilator, the clock is generated in C++ code and passed into
    // this module. for other simulators, the clock is generated in Verilog
    // in this module.

    `ifdef VERILATOR
        input clk
    `endif
);
    ///////////////////////
    // EBRICK parameters //
    ///////////////////////

    localparam W        = 2;
    localparam H        = 2;
    localparam RW       = 32;
    localparam DW       = 32;
    localparam AW       = 64;
    localparam CW       = 32;
    localparam IDW      = 16;
    localparam NPT      = 2;
    localparam NAIO     = 2;
    localparam NGPIO    = 16;
    localparam RAMDEPTH = `MAIN_MEMORY_SIZE/(DW/8);
    localparam W2       = W/2;
    localparam H2       = H/2;

    //////////////////////
    // clock generation //
    //////////////////////

    `ifndef VERILATOR
        localparam PERIOD_CLK = 10;

        reg clk = 1'b0;

        always begin
            #(PERIOD_CLK/2) clk = ~clk;
        end
    `endif

    ///////////////////////////////
    // ebrick_core instantiation //
    ///////////////////////////////

    wire            nreset;
    wire            go;
    wire [IDW-1:0]  chipid;
    wire [RW-1:0]   status;

    `UMI_WIRES(core2mtr_req, DW, CW, AW);
    `UMI_WIRES(mtr2core_resp, DW, CW, AW);

    assign chipid = `CORE_CHIPID;

    ebrick_core #(
        .W      (W),
        .H      (H),
        .NPT    (NPT),
        .NAIO   (NAIO),
        .NGPIO  (NGPIO),
        .RW     (RW),
        .DW     (DW),
        .IDW    (IDW),
        .AW     (AW),
        .CW     (CW)
    ) ebrick_core_ (
        // global ebrick controls (from clink0/ebrick_regs/bus)
        .clk                (clk),
        .auxclk             (4'b0),
        .nreset             (nreset),
        .go                 (go),
        .testmode           (1'b0),
        .chipletmode        (2'b00),
        .chipdir            (2'b00),
        .chipid             ({{IDW*(W*H-1){1'b0}}, chipid}),
        .irq_in             (64'b0),
        .irq_out            (),

        // JTAG interface (from a core or looped in->out)
        .jtag_tck           (1'b0),
        .jtag_tms           (1'b0),
        .jtag_tdi           (1'b0),
        .jtag_tdo           (),
        .jtag_tdo_oe        (),

        // general controls
        .ctrl               ({RW{1'b0}}),
        .status             (status),
        .initdone           (),
        .test_scanmode      (1'b0),
        .test_scanenable    (1'b0),
        .test_scanin        (1'b0),
        .test_scanout       (),

        // Host ports (one per CLINK)

        /* verilator lint_off WIDTHEXPAND */

        .uhost_req_valid    (core2mtr_req_valid),
        .uhost_req_cmd      (core2mtr_req_cmd),
        .uhost_req_dstaddr  (core2mtr_req_dstaddr),
        .uhost_req_srcaddr  (core2mtr_req_srcaddr),
        .uhost_req_data     (core2mtr_req_data),
        .uhost_req_ready    ({{(W*H-1){1'b0}}, core2mtr_req_ready}),

        .uhost_resp_valid   ({{(W*H-1){1'b0}}, mtr2core_resp_valid}),
        .uhost_resp_cmd     ({{CW*(W*H-1){1'b0}}, mtr2core_resp_cmd}),
        .uhost_resp_dstaddr ({{AW*(W*H-1){1'b0}}, mtr2core_resp_dstaddr}),
        .uhost_resp_srcaddr ({{AW*(W*H-1){1'b0}}, mtr2core_resp_srcaddr}),
        .uhost_resp_data    ({{DW*(W*H-1){1'b0}}, mtr2core_resp_data}),
        .uhost_resp_ready   (mtr2core_resp_ready),

        /* verilator lint_on WIDTHEXPAND */

        // Device ports (one per CLINK)
        .udev_req_valid     ({W*H{1'b0}}),
        .udev_req_cmd       ({CW*W*H{1'b0}}),
        .udev_req_dstaddr   ({AW*W*H{1'b0}}),
        .udev_req_srcaddr   ({AW*W*H{1'b0}}),
        .udev_req_data      ({DW*W*H{1'b0}}),
        .udev_req_ready     (),

        .udev_resp_valid    (),
        .udev_resp_cmd      (),
        .udev_resp_dstaddr  (),
        .udev_resp_srcaddr  (),
        .udev_resp_data     (),
        .udev_resp_ready    ({W*H{1'b0}}),

        // GPIO
        .no_txgpio          (),
        .no_txgpiooe        (),
        .no_rxgpio          ({W2*NGPIO{1'b0}}),

        .ea_txgpio          (),
        .ea_txgpiooe        (),
        .ea_rxgpio          ({H2*NGPIO{1'b0}}),

        .so_txgpio          (),
        .so_txgpiooe        (),
        .so_rxgpio          ({W2*NGPIO{1'b0}}),

        .we_txgpio          (),
        .we_txgpiooe        (),
        .we_rxgpio          ({H2*NGPIO{1'b0}}),

        // IO
        .no_analog          (),
        .ea_analog          (),
        .so_analog          (),
        .we_analog          (),
        .pad_nptn           (),
        .pad_eptn           (),
        .pad_sptn           (),
        .pad_wptn           (),
        .pad_nptp           (),
        .pad_eptp           (),
        .pad_sptp           (),
        .pad_wptp           (),

        // Memory macro control signals - should connect to the sram wrappers
        .csr_rf_ctrl        (8'b0),
        .csr_sram_ctrl      (8'b0),

        // supplies
        .vss                (),
        .vdd                (),
        .vddx               (),
        .vcc                (),
        .vdda               ()
    );

    /////////////////////////////////////////////////
    // switchboard connections to EBRICK UMI ports //
    /////////////////////////////////////////////////

    // ebrick_core (PicoRV32) is the UMI host
    // monitor (Python) is the UMI device

    umi_to_queue_sim #(
        .READY_MODE_DEFAULT(2),
        .DW(DW)
    ) core2mtr_i (
        .clk            (clk),
        `UMI_CONNECT_SB (core2mtr_req)
    );

    queue_to_umi_sim #(
        .VALID_MODE_DEFAULT(2),
        .DW(DW)
    ) mtr2core_i (
        .clk            (clk),
        `UMI_CONNECT_SB (mtr2core_resp)
    );

    //////////////
    // umi_gpio //
    //////////////

    // reset signal just for the umi_gpio block. this needs to be driven
    // from Verilog, rather than Python, because umi_gpio drives the
    // nreset signal for all other blocks.

    reg gpio_nreset = 1'b0;

    always @(posedge clk) begin
        gpio_nreset <= 1'b1;
    end

    // umi_gpio instantiation

    `UMI_WIRES(gpio_in, DW, CW, AW);
    `UMI_WIRES(gpio_out, DW, CW, AW);

    umi_gpio #(
        .DW     (DW),
        .AW     (AW),
        .CW     (CW),
        .IWIDTH (32),
        .OWIDTH (32)
    ) umi_gpio_ (
        .clk                (clk),
        .nreset             (gpio_nreset),

        .gpio_in            (status),
        /* verilator lint_off WIDTHEXPAND */
        .gpio_out           ({go, nreset}),
        /* verilator lint_on WIDTHEXPAND */

        `UMI_CONNECT        (udev_req, gpio_in),
        `UMI_CONNECT        (udev_resp, gpio_out)
    );

    // switchboard connections for the umi_gpio instance

    // Python is the UMI host
    // umi_gpio is the UMI device

    queue_to_umi_sim #(
        .VALID_MODE_DEFAULT(2),
        .DW(DW)
    ) host2gpio_i (
        .clk            (clk),
        `UMI_CONNECT_SB (gpio_in)
    );

    umi_to_queue_sim #(
        .READY_MODE_DEFAULT(2),
        .DW(DW)
    ) gpio2host_i (
        .clk            (clk),
        `UMI_CONNECT_SB (gpio_out)
    );

    // initialize switchboard connections

    initial begin
        /* verilator lint_off IGNOREDRETURN */

        // get runtime options indicating the desired behavior of
        // ready/valid handshaking by switchboard modules. for more
        // details, see https://github.com/zeroasiccorp/switchboard/tree/main/examples/umiram

        integer valid_mode, ready_mode;

        if (!$value$plusargs("valid_mode=%d", valid_mode)) begin
           valid_mode = 2;  // default if not provided as a plusarg
        end

        if (!$value$plusargs("ready_mode=%d", ready_mode)) begin
           ready_mode = 2;  // default if not provided as a plusarg
        end

        ////////////////////////////////////
        // switchboard queues for monitor //
        ////////////////////////////////////

        // queue names must match definitions in
        // the Python test script (test_prv32.py)

        core2mtr_i.init("core2mtr_0.q");
        core2mtr_i.set_ready_mode(ready_mode);
        mtr2core_i.init("mtr2core_0.q");
        mtr2core_i.set_valid_mode(valid_mode);

        /////////////////////////////////
        // switchboard queues for GPIO //
        /////////////////////////////////

        // queue names must match definitions in
        // the Python test script (test_prv32.py)

        host2gpio_i.init("host2gpio_0.q");
        host2gpio_i.set_valid_mode(valid_mode);
        gpio2host_i.init("gpio2host_0.q");
        gpio2host_i.set_ready_mode(ready_mode);
    end

    // Waveform probing

    initial begin
        if ($test$plusargs("trace")) begin
            $dumpfile("testbench.vcd");
            $dumpvars(0, testbench);
        end
    end

endmodule

`default_nettype wire
