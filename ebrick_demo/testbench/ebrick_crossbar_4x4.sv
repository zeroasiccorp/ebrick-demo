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
 *  This is a 4x4 Crossbar
 *  There are 4 UMI device ports servicing:
 *      1. Incoming UMI request from ebrick_core
 *      2. Incoming UMI request from UMITxRx host2mem_i
 *      3. Incoming UMI response from umi_mem_agent
 *      4. Incoming UMI response from UMITxRx mtr2core_i
 *
 *  There are 4 UMI host ports issuing:
 *      1. Outgoing UMI response to ebrick_core
 *      2. Outgoing UMI response to UMITxRx mem2host_i
 *      3. Outgoing UMI request to umi_mem_agent
 *      4. Outgoing UMI request to UMITxRx core2mtr_i
 *
 *  Outgoing -> (core_resp) (host_resp) (mem_req) (monitor_req)
 *  Incoming
 *     |
 *     V
 *  (core_req)       N           N          Y           Y
 *  (host_req)       N           N          Y           N
 *  (mem_resp)       Y           Y          N           N
 *  (monitor_resp)   Y           N          N           N
 *
 *  Y denotes a connection meaning a UMI transaction with the appropriate
 *  source and destination address will proceed along that link.
 *  N denotes no connection meaning a UMI transaction along that link will be
 *  rejected.
 *
 *  While the address map is tailored for a specific example, it can be
 *  modified in the Address Map section below to create any 4x4 crossbar
 *  configuration.
 *  The mask bits decide whether a legal transction exists along a link from
 *  an input device port to an output host port. While they are tailored for
 *  a specific example as well, they can be changed in the mask section below.
 *
 ****************************************************************************/

`include "ebrick_memory_map.vh"
`include "umi_macros.vh"

 module ebrick_crossbar_4x4 #(
    parameter TARGET    = "DEFAULT",// compiler target
    parameter CW        = 32,       // command width
    parameter AW        = 64,       // address width
    parameter DW        = 32,       // packet width
    parameter IDW       = 16        // chipid width
)
(
    input               clk,            // main clock signal
    input               nreset,         // async active low reset

    `UMI_INPUT_ARRAY    (udev, DW, CW, AW, 4),  // 4x Input UMI ports

    `UMI_OUTPUT_ARRAY   (uhost, DW, CW, AW, 4)  // 4x Output UMI ports
);

    // Mask
    // Mask is based on the table denoting legality above
    // Mask = 0 denotes a legal link
    // Mask = 1 denotes an illegal link
    wire [15:0] mask;

    // Core Response Port Mask
    assign mask[0]  = 1;
    assign mask[1]  = 1;
    assign mask[2]  = 0;
    assign mask[3]  = 0;

    // Host Response Port Mask
    assign mask[4]  = 1;
    assign mask[5]  = 1;
    assign mask[6]  = 0;
    assign mask[7]  = 1;

    // Memory Request Port Mask
    assign mask[8]  = 0;
    assign mask[9]  = 0;
    assign mask[10] = 1;
    assign mask[11] = 1;

    // Monitor Request Port Mask
    assign mask[12] = 0;
    assign mask[13] = 1;
    assign mask[14] = 1;
    assign mask[15] = 1;

    // UMI Transaction orchestration
    wire [15:0] umi_in_request;

    genvar i;

    for (i = 0; i < 4; i = i + 1) begin : UMI_TX_SEL
        assign umi_in_request[i]    = udev_valid[i] &
                                      (udev_dstaddr[i*AW+:AW] >= `CORE_ADDR_LOW) &
                                      (udev_dstaddr[i*AW+:AW] <= `CORE_ADDR_HIGH);

        assign umi_in_request[i+4]  = udev_valid[i] &
                                      (udev_dstaddr[i*AW+:AW] >= `HOST_ADDR_LOW) &
                                      (udev_dstaddr[i*AW+:AW] <= `HOST_ADDR_HIGH);

        /* verilator lint_off UNSIGNED */
        assign umi_in_request[i+8]  = udev_valid[i] &
                                      (udev_dstaddr[i*AW+:AW] >= `MEM_ADDR_LOW) &
                                      (udev_dstaddr[i*AW+:AW] <= `MEM_ADDR_HIGH);
        /* verilator lint_on UNSIGNED */

        assign umi_in_request[i+12] = udev_valid[i] &
                                      (udev_dstaddr[i*AW+:AW] >= `MONITOR_ADDR_LOW) &
                                      (udev_dstaddr[i*AW+:AW] <= `MONITOR_ADDR_HIGH);
    end

    umi_crossbar #(
        .TARGET     (TARGET),
        .DW         (DW),
        .CW         (CW),
        .AW         (AW),
        .N          (4)
    ) umi_crossbar_ (
        // controls
        .clk                (clk),
        .nreset             (nreset),
        .mode               (2'b10),
        .mask               (mask),

        // Incoming UMI
        .umi_in_request     (umi_in_request),
        .umi_in_cmd         (udev_cmd),
        .umi_in_dstaddr     (udev_dstaddr),
        .umi_in_srcaddr     (udev_srcaddr),
        .umi_in_data        (udev_data),
        .umi_in_ready       (udev_ready),

        // Outgoing UMI
        `UMI_CONNECT        (umi_out, uhost)
    );

endmodule
