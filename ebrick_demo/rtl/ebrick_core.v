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
 *
 * 1. The dimensions of an EBRICK are denoted WxH, where W is the width of
 *    the brick in mm, and H is the height in mm (both are integer values).
 * 2. The EBRICK pinout is a WxH array of CLINKs, each 1x1 mm. Each CLINK
 *    contains one UMI host port and one UMI device port, among other
 *    signals.
 * 3. In the ebrick_core interface, arrays of signals are serialized as vectors
 *    to interoperate with legacy Verilog systems. For example, in a 2x2 EBRICK:
 *    uhost_req_data[DW-1:0] corresponds to CLINK[0][0]
 *    uhost_req_data[2*DW-1:DW] corresponds to CLINK[0][1]
 *    uhost_req_data[3*DW-1:2*DW] corresponds to CLINK[1][0]
 *    uhost_req_data[4*DW-1:3*DW] corresponds to CLINK[1][1]
 * 4. Floating core outputs are not allowed.
 *
 ****************************************************************************/

`include "ebrick_memory_map.vh"

module ebrick_core #(
    parameter TARGET = "DEFAULT", // technology target
    parameter W = 2,              // brick width (mm) (1,2,3,4,5)
    parameter H = 2,              // brick height (mm) (1,2,3,4,5)
    parameter NPT = 2,            // pass-through per link
    parameter NAIO = 2,           // analog io per clink
    parameter NGPIO = 16,         // number of GPIO pins per side for each clink/2mm side
    parameter RW = 32,            // umi packet width
    parameter DW = 32,            // umi packet width
    parameter IDW = 16,           // brick ID width
    parameter AW = 64,            // address width
    parameter CW = 32,            // command width
    // derived
    parameter W2 = W/2,           // 2D clinks (width, multiple of 2mm)
    parameter H2 = H/2            // 2D clinks (height, multiple of 2mm)
) (
    // global ebrick controls (from clink0/ebrick_regs/bus)
    input                 clk,         // main clock signal
    input [3:0]           auxclk,      // auxiliary clock signals
    input                 nreset,      // async active low reset
    input                 go,          // 1=start/boot core
    input                 testmode,    // 1=connect brick IO directly to core.
    input [1:0]           chipletmode, // 00=150um,01=45um,10=10um,11=1um
    input [1:0]           chipdir,     // brick direction (wrt fabric)
    input [W*H*IDW-1:0]   chipid,      // unique brick id
    input [63:0]          irq_in,      // interrupts vector to the core
    output [63:0]         irq_out,     // interrupts vector to the ebrick cpu

    // JTAG interface (from a core or looped in->out)
    input                 jtag_tck,
    input                 jtag_tms,
    input                 jtag_tdi,
    output                jtag_tdo,
    output                jtag_tdo_oe,

    // general controls
    input [RW-1:0]        ctrl,        // generic control vector
    output [RW-1:0]       status,      // generic status
    output                initdone,    // generic status
    input                 test_scanmode,
    input                 test_scanenable,
    input                 test_scanin,
    output                test_scanout,

    // Host ports (one per CLINK)
    output [W*H-1:0]      uhost_req_valid,
    output [W*H*CW-1:0]   uhost_req_cmd,
    output [W*H*AW-1:0]   uhost_req_dstaddr,
    output [W*H*AW-1:0]   uhost_req_srcaddr,
    output [W*H*DW-1:0]   uhost_req_data,
    input [W*H-1:0]       uhost_req_ready,
    input [W*H-1:0]       uhost_resp_valid,
    input [W*H*CW-1:0]    uhost_resp_cmd,
    input [W*H*AW-1:0]    uhost_resp_dstaddr,
    input [W*H*AW-1:0]    uhost_resp_srcaddr,
    input [W*H*DW-1:0]    uhost_resp_data,
    output [W*H-1:0]      uhost_resp_ready,

    // Device ports (one per CLINK)
    input [W*H-1:0]       udev_req_valid,
    input [W*H*CW-1:0]    udev_req_cmd,
    input [W*H*AW-1:0]    udev_req_dstaddr,
    input [W*H*AW-1:0]    udev_req_srcaddr,
    input [W*H*DW-1:0]    udev_req_data,
    output [W*H-1:0]      udev_req_ready,
    output [W*H-1:0]      udev_resp_valid,
    output [W*H*CW-1:0]   udev_resp_cmd,
    output [W*H*AW-1:0]   udev_resp_dstaddr,
    output [W*H*AW-1:0]   udev_resp_srcaddr,
    output [W*H*DW-1:0]   udev_resp_data,
    input [W*H-1:0]       udev_resp_ready,

    // GPIO - same interface for 2D and 3D
    // [W,H] each clink i/f has no, ea, we and so IO
    // each io side hase two banks
    // only the corner one connect to the padmap
    output [W2*NGPIO-1:0] no_txgpio,
    output [W2*NGPIO-1:0] no_txgpiooe,
    input [W2*NGPIO-1:0]  no_rxgpio,

    output [H2*NGPIO-1:0] ea_txgpio,
    output [H2*NGPIO-1:0] ea_txgpiooe,
    input [H2*NGPIO-1:0]  ea_rxgpio,

    output [W2*NGPIO-1:0] so_txgpio,
    output [W2*NGPIO-1:0] so_txgpiooe,
    input [W2*NGPIO-1:0]  so_rxgpio,

    output [H2*NGPIO-1:0] we_txgpio,
    output [H2*NGPIO-1:0] we_txgpiooe,
    input [H2*NGPIO-1:0]  we_rxgpio,

    // IO
    inout [W2*NAIO-1:0]   no_analog,   // analog interface through padring
    inout [H2*NAIO-1:0]   ea_analog,   // analog interface through padring
    inout [W2*NAIO-1:0]   so_analog,   // analog interface through padring
    inout [H2*NAIO-1:0]   we_analog,   // analog interface through padring
    inout [W*H*NPT-1:0]   pad_nptn,    // pass through inputs
    inout [W*H*NPT-1:0]   pad_eptn,    // pass through inputs
    inout [W*H*NPT-1:0]   pad_sptn,    // pass through inputs
    inout [W*H*NPT-1:0]   pad_wptn,    // pass through inputs
    inout [W*H*NPT-1:0]   pad_nptp,    // pass through inputs
    inout [W*H*NPT-1:0]   pad_eptp,    // pass through inputs
    inout [W*H*NPT-1:0]   pad_sptp,    // pass through inputs
    inout [W*H*NPT-1:0]   pad_wptp,    // pass through inputs

    // Memory macro control signals - should connect to the SRAM wrappers
    input [7:0]           csr_rf_ctrl,
    input [7:0]           csr_sram_ctrl,

    // Supplies
    input                 vss,
    input                 vdd,
    input                 vddx,
    input [3:0]           vcc,
    input [3:0]           vdda
);
    ///////////////////////////
    // reset synchronization //
    ///////////////////////////

    wire    nrst_out;
    wire    synced_nreset;

    la_rsync nreset_sync_i (
        .clk        (clk),
        .nrst_in    (nreset),
        .nrst_out   (nrst_out)
    );

    assign synced_nreset = nrst_out && go;

    //////////////
    // tie-offs //
    //////////////

    // The JTAG interface is designed to connect to a JTAG controller inside the core.
    // If the core does not have a JTAG controller, the interface should be looped
    // based on the example below.

    assign jtag_tdo    = jtag_tdi;
    assign jtag_tdo_oe = 1'b1;

    // Outputs must be driven, even if you don't use them!
    assign irq_out[63:32]                 = 'h0;
    assign test_scanout                   = 1'b0;
    assign status[RW-1:1]                 = 'h0;
    assign initdone                       = 'b0;

    // Tie off GPIOs
    assign no_txgpio[W2*NGPIO-1:0]        = 'b0;
    assign no_txgpiooe[W2*NGPIO-1:0]      = 'b0;

    assign ea_txgpio[H2*NGPIO-1:0]        = 'b0;
    assign ea_txgpiooe[H2*NGPIO-1:0]      = 'b0;

    assign so_txgpio[W2*NGPIO-1:0]        = 'b0;
    assign so_txgpiooe[W2*NGPIO-1:0]      = 'b0;

    assign we_txgpio[H2*NGPIO-1:0]        = 'b0;
    assign we_txgpiooe[H2*NGPIO-1:0]      = 'b0;

    // Tie off unused UMI host ports
    assign uhost_resp_ready[W*H-1:1]      = {(W*H-1){1'b0}};
    assign uhost_req_valid[W*H-1:1]       = {(W*H-1){1'b0}};
    assign uhost_req_cmd[W*H*CW-1:CW]     = {CW*(W*H-1){1'b0}};
    assign uhost_req_dstaddr[W*H*AW-1:AW] = {AW*(W*H-1){1'b0}};
    assign uhost_req_srcaddr[W*H*AW-1:AW] = {AW*(W*H-1){1'b0}};
    assign uhost_req_data[W*H*DW-1:DW]    = {DW*(W*H-1){1'b0}};

    // Tie off unused UMI device ports
    assign udev_req_ready[W*H-1:0]        = {(W*H){1'b0}};
    assign udev_resp_valid[W*H-1:0]       = {(W*H){1'b0}};
    assign udev_resp_cmd[W*H*CW-1:0]      = {CW*W*H{1'b0}};
    assign udev_resp_dstaddr[W*H*AW-1:0]  = {AW*W*H{1'b0}};
    assign udev_resp_srcaddr[W*H*AW-1:0]  = {AW*W*H{1'b0}};
    assign udev_resp_data[W*H*DW-1:0]     = {DW*W*H{1'b0}};

    //////////////
    // PicoRV32 //
    //////////////

    // Declare AXI4-lite interface

    wire        mem_axi_awvalid;
    wire        mem_axi_awready;
    wire [31:0] mem_axi_awaddr;
    wire [2:0]  mem_axi_awprot;

    wire        mem_axi_wvalid;
    wire        mem_axi_wready;
    wire [31:0] mem_axi_wdata;
    wire [3:0]  mem_axi_wstrb;

    wire        mem_axi_bvalid;
    wire        mem_axi_bready;
    wire [1:0]  mem_axi_bresp;

    wire        mem_axi_arvalid;
    wire        mem_axi_arready;
    wire [31:0] mem_axi_araddr;
    wire [2:0]  mem_axi_arprot;

    wire        mem_axi_rvalid;
    wire        mem_axi_rready;
    wire [31:0] mem_axi_rdata;
    wire [1:0]  mem_axi_rresp;

    // Instantiate PicoRV32
    // https://github.com/YosysHQ/picorv32/tree/a7b56fc81ff1363d20fd0fb606752458cd810552

    picorv32_axi #(
        .ENABLE_MUL(1),
        .ENABLE_DIV(1),
        .ENABLE_IRQ(1),
        .ENABLE_TRACE(1),
        .COMPRESSED_ISA(0)
    ) picorv32_axi_ (
        .clk                (clk),
        .resetn             (synced_nreset),
        .trap               (status[0]),

        // AXI4-lite master memory interface
        .mem_axi_awvalid    (mem_axi_awvalid),
        .mem_axi_awready    (mem_axi_awready),
        .mem_axi_awaddr     (mem_axi_awaddr),
        .mem_axi_awprot     (mem_axi_awprot),

        .mem_axi_wvalid     (mem_axi_wvalid),
        .mem_axi_wready     (mem_axi_wready),
        .mem_axi_wdata      (mem_axi_wdata),
        .mem_axi_wstrb      (mem_axi_wstrb),

        .mem_axi_bvalid     (mem_axi_bvalid),
        .mem_axi_bready     (mem_axi_bready),

        .mem_axi_arvalid    (mem_axi_arvalid),
        .mem_axi_arready    (mem_axi_arready),
        .mem_axi_araddr     (mem_axi_araddr),
        .mem_axi_arprot     (mem_axi_arprot),

        .mem_axi_rvalid     (mem_axi_rvalid),
        .mem_axi_rready     (mem_axi_rready),
        .mem_axi_rdata      (mem_axi_rdata),

        // Pico Co-Processor Interface (PCPI)
        .pcpi_valid         (),
        .pcpi_insn          (),
        .pcpi_rs1           (),
        .pcpi_rs2           (),
        .pcpi_wr            (),
        .pcpi_rd            (),
        .pcpi_wait          (),
        .pcpi_ready         (),

        // IRQ interface
        .irq                (irq_in[31:0]),
        .eoi                (irq_out[31:0]),

        // Trace Interface
        .trace_valid        (),
        .trace_data         ()
    );

    //////////////////////
    // AXI4-Lite to UMI //
    //////////////////////

    wire [AW-1:0]   uhost_req_dstaddr_out;

    axilite2umi #(
        .CW                 (CW),
        .AW                 (AW),
        .DW                 (DW),
        .IDW                (IDW)
    ) axilite2umi_ (
        .clk                (clk),
        .nreset             (synced_nreset),

        .chipid             (chipid[IDW-1:0]),
        .local_routing      (16'h0000),

        // AXI4-Lite interface

        .axi_awaddr         ({32'h0, mem_axi_awaddr}),
        .axi_awprot         (mem_axi_awprot),
        .axi_awvalid        (mem_axi_awvalid),
        .axi_awready        (mem_axi_awready),

        .axi_wdata          (mem_axi_wdata),
        .axi_wstrb          (mem_axi_wstrb),
        .axi_wvalid         (mem_axi_wvalid),
        .axi_wready         (mem_axi_wready),

        .axi_bresp          (mem_axi_bresp),
        .axi_bvalid         (mem_axi_bvalid),
        .axi_bready         (mem_axi_bready),

        .axi_araddr         ({32'h0, mem_axi_araddr}),
        .axi_arprot         (mem_axi_arprot),
        .axi_arvalid        (mem_axi_arvalid),
        .axi_arready        (mem_axi_arready),

        .axi_rdata          (mem_axi_rdata),
        .axi_rresp          (mem_axi_rresp),
        .axi_rvalid         (mem_axi_rvalid),
        .axi_rready         (mem_axi_rready),

        // Host port

        .uhost_req_valid    (uhost_req_valid[0]),
        .uhost_req_cmd      (uhost_req_cmd[CW-1:0]),
        .uhost_req_dstaddr  (uhost_req_dstaddr_out[AW-1:0]),
        .uhost_req_srcaddr  (uhost_req_srcaddr[AW-1:0]),
        .uhost_req_data     (uhost_req_data[DW-1:0]),
        .uhost_req_ready    (uhost_req_ready[0]),

        .uhost_resp_valid   (uhost_resp_valid[0]),
        .uhost_resp_cmd     (uhost_resp_cmd[CW-1:0]),
        .uhost_resp_dstaddr (uhost_resp_dstaddr[AW-1:0]),
        .uhost_resp_srcaddr (uhost_resp_srcaddr[AW-1:0]),
        .uhost_resp_data    (uhost_resp_data[DW-1:0]),
        .uhost_resp_ready   (uhost_resp_ready[0])
    );

    // If destination address is less than max RAM size, direct packet to
    // main memory, else send it to monitor
    assign uhost_req_dstaddr[AW-1:0] = (uhost_req_dstaddr_out < {24'h0, `MAIN_MEMORY_SIZE}) ?
                                       {8'b0, `MEM_CHIPID, uhost_req_dstaddr_out[39:0]} :
                                       {8'b0, `MONITOR_CHIPID, uhost_req_dstaddr_out[39:0]};

endmodule
