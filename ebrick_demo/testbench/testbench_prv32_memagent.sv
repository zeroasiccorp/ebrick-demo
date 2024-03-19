// Copyright (c) 2024 Zero ASIC Corporation
// This code is licensed under Apache License 2.0 (see LICENSE for details)

`default_nettype none

`include "ebrick_memory_map.vh"
`include "umi_macros.vh"

module testbench (
`ifdef VERILATOR
    input clk
`endif
);

    localparam PERIOD_CLK = 10;

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

`ifndef VERILATOR
    reg clk;

    initial
        clk  = 1'b0;
    always #(PERIOD_CLK/2) clk = ~clk;
`endif

    wire            nreset;
    wire            go;
    wire [IDW-1:0]  chipid;
    wire [RW-1:0]   status;

    reg go_nreset = 1'b0;

    always @(posedge clk) begin
        go_nreset <= 1'b1;
    end

    `UMI_WIRES(gpio_in, DW, CW, AW);
    `UMI_WIRES(gpio_out, DW, CW, AW);

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

    umi_gpio #(
        .DW     (DW),
        .AW     (AW),
        .CW     (CW),
        .IWIDTH (32),
        .OWIDTH (32)
    ) umi_gpio_ (
        .clk                (clk),
        .nreset             (go_nreset),

        .gpio_in            (status),
        /* verilator lint_off WIDTHEXPAND */
        .gpio_out           ({go, nreset}),
        /* verilator lint_on WIDTHEXPAND */

        `UMI_CONNECT        (udev_req, gpio_in),
        `UMI_CONNECT        (udev_resp, gpio_out)
    );

    // UMITxRx to monitor transactions
    // that are beyond memory address space
    // i.e. [0 to ((DW*RAMDEPTH/8)-1)]
    //
    // ebrick_core (picorv2) is the UMI host
    // Monitor (python) is the UMI device
    `UMI_WIRES(core2mtr_req, DW, CW, AW);
    `UMI_WIRES(mtr2core_resp, DW, CW, AW);

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

    // ebrick_core UMI Host
    wire            core_uhost_req_valid;
    wire [CW-1:0]   core_uhost_req_cmd;
    wire [AW-1:0]   core_uhost_req_dstaddr;
    wire [AW-1:0]   core_uhost_req_srcaddr;
    wire [DW-1:0]   core_uhost_req_data;
    wire            core_uhost_req_ready;

    wire            core_uhost_resp_valid;
    wire [CW-1:0]   core_uhost_resp_cmd;
    wire [AW-1:0]   core_uhost_resp_dstaddr;
    wire [AW-1:0]   core_uhost_resp_srcaddr;
    wire [DW-1:0]   core_uhost_resp_data;
    wire            core_uhost_resp_ready;

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

        // Jtag interface (from a core or looped in->out)
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

        // Host port (per clink)

        /* verilator lint_off WIDTHEXPAND */

        .uhost_req_valid    (core_uhost_req_valid),
        .uhost_req_cmd      (core_uhost_req_cmd),
        .uhost_req_dstaddr  (core_uhost_req_dstaddr),
        .uhost_req_srcaddr  (core_uhost_req_srcaddr),
        .uhost_req_data     (core_uhost_req_data),
        .uhost_req_ready    ({{(W*H-1){1'b0}}, core_uhost_req_ready}),

        .uhost_resp_valid   ({{(W*H-1){1'b0}}, core_uhost_resp_valid}),
        .uhost_resp_cmd     ({{CW*(W*H-1){1'b0}}, core_uhost_resp_cmd}),
        .uhost_resp_dstaddr ({{AW*(W*H-1){1'b0}}, core_uhost_resp_dstaddr}),
        .uhost_resp_srcaddr ({{AW*(W*H-1){1'b0}}, core_uhost_resp_srcaddr}),
        .uhost_resp_data    ({{DW*(W*H-1){1'b0}}, core_uhost_resp_data}),
        .uhost_resp_ready   (core_uhost_resp_ready),

        /* verilator lint_on WIDTHEXPAND */

        // Device port (per clink)
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

    // UMITxRx to intialize/load main memory
    // Python is the UMI host (named host here)
    // umi_mem_agent is the UMI device
    `UMI_WIRES(host2mem_req, DW, CW, AW);
    `UMI_WIRES(mem2host_resp, DW, CW, AW);

    queue_to_umi_sim #(
        .VALID_MODE_DEFAULT(2),
        .DW(DW)
    ) host2mem_i (
        .clk            (clk),
        `UMI_CONNECT_SB (host2mem_req)
    );

    umi_to_queue_sim #(
        .READY_MODE_DEFAULT(2),
        .DW(DW)
    ) mem2host_i (
        .clk            (clk),
        `UMI_CONNECT_SB (mem2host_resp)
    );

    // Main Memory Device Port
    `UMI_WIRES(main_mem_req, DW, CW, AW);
    `UMI_WIRES(main_mem_resp, DW, CW, AW);

    umi_mem_agent #(
        .DW                 (DW),
        .AW                 (AW),
        .CW                 (CW),
        .RAMDEPTH           (RAMDEPTH)
    ) umi_main_memory_ (
        .clk                (clk),
        .nreset             (nreset),
        .sram_ctrl          (8'b0),

        // Device port
        `UMI_CONNECT        (udev_req, main_mem_req),
        `UMI_CONNECT        (udev_resp, main_mem_resp)
    );

    // Crossbar connections
    `UMI_WIRES_ARRAY    (crossbar_udev, DW, CW, AW, 4);
    `UMI_WIRES_ARRAY    (crossbar_uhost, DW, CW, AW, 4);

    assign crossbar_udev_valid   = {mtr2core_resp_valid,
                                    main_mem_resp_valid,
                                    host2mem_req_valid,
                                    core_uhost_req_valid};
    assign crossbar_udev_cmd     = {mtr2core_resp_cmd,
                                    main_mem_resp_cmd,
                                    host2mem_req_cmd,
                                    core_uhost_req_cmd};
    assign crossbar_udev_dstaddr = {mtr2core_resp_dstaddr,
                                    main_mem_resp_dstaddr,
                                    host2mem_req_dstaddr,
                                    core_uhost_req_dstaddr};
    assign crossbar_udev_srcaddr = {mtr2core_resp_srcaddr,
                                    main_mem_resp_srcaddr,
                                    host2mem_req_srcaddr,
                                    core_uhost_req_srcaddr};
    assign crossbar_udev_data    = {mtr2core_resp_data,
                                    main_mem_resp_data,
                                    host2mem_req_data,
                                    core_uhost_req_data};
    assign {mtr2core_resp_ready,
            main_mem_resp_ready,
            host2mem_req_ready,
            core_uhost_req_ready} = crossbar_udev_ready;

    assign {core2mtr_req_valid,
            main_mem_req_valid,
            mem2host_resp_valid,
            core_uhost_resp_valid}   = crossbar_uhost_valid;
    assign {core2mtr_req_cmd,
            main_mem_req_cmd,
            mem2host_resp_cmd,
            core_uhost_resp_cmd}     = crossbar_uhost_cmd;
    assign {core2mtr_req_dstaddr,
            main_mem_req_dstaddr,
            mem2host_resp_dstaddr,
            core_uhost_resp_dstaddr} = crossbar_uhost_dstaddr;
    assign {core2mtr_req_srcaddr,
            main_mem_req_srcaddr,
            mem2host_resp_srcaddr,
            core_uhost_resp_srcaddr} = crossbar_uhost_srcaddr;
    assign {core2mtr_req_data,
            main_mem_req_data,
            mem2host_resp_data,
            core_uhost_resp_data}    = crossbar_uhost_data;
    assign crossbar_uhost_ready      = {core2mtr_req_ready,
                                        main_mem_req_ready,
                                        mem2host_resp_ready,
                                        core_uhost_resp_ready};

    ebrick_crossbar_4x4 #(
        .CW     (CW),
        .AW     (AW),
        .DW     (DW),
        .IDW    (IDW)
    ) ebrick_crossbar_4x4_ (
        .clk            (clk),
        .nreset         (nreset),

        `UMI_CONNECT    (udev, crossbar_udev),
        `UMI_CONNECT    (uhost, crossbar_uhost)
    );

    // Initialize UMI
    integer valid_mode, ready_mode;

    initial begin
        /* verilator lint_off IGNOREDRETURN */
        if (!$value$plusargs("valid_mode=%d", valid_mode)) begin
           valid_mode = 2;  // default if not provided as a plusarg
        end

        if (!$value$plusargs("ready_mode=%d", ready_mode)) begin
           ready_mode = 2;  // default if not provided as a plusarg
        end

        // UMI queues for main memory loader
        // Python is the UMI host (named host here)
        // umi_mem_agent is the UMI device
        host2mem_i.init("host2mem_0.q");
        host2mem_i.set_valid_mode(valid_mode);
        mem2host_i.init("mem2host_0.q");
        mem2host_i.set_ready_mode(ready_mode);

        // UMI queues for monitor
        // ebrick_core (picorv2) is the UMI host
        // Monitor (python) is the UMI device
        core2mtr_i.init("core2mtr_0.q");
        core2mtr_i.set_ready_mode(ready_mode);
        mtr2core_i.init("mtr2core_0.q");
        mtr2core_i.set_valid_mode(valid_mode);

        // UMI queues for GPIO
        // Python is the UMI host (named host here)
        // gpio is the UMI device
        host2gpio_i.init("host2gpio_0.q");
        host2gpio_i.set_valid_mode(valid_mode);
        gpio2host_i.init("gpio2host_0.q");
        gpio2host_i.set_ready_mode(ready_mode);
    end

    // VCD
    initial begin
        if ($test$plusargs("trace")) begin
            `ifdef VERILATOR
                $dumpfile("testbench.vcd");
                $dumpvars(0, testbench);
            `elsif __ICARUS__
                $dumpfile("testbench.vcd");
                $dumpvars(0, testbench);
            `endif
        end
    end

endmodule

`default_nettype wire
