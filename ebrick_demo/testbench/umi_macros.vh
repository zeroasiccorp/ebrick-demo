// Copyright (c) 2024 Zero ASIC Corporation
// This code is licensed under Apache License 2.0 (see LICENSE for details)

// Macros to simplify the process of making UMI connections

`ifndef __UMI_MACROS_VH__
`define __UMI_MACROS_VH__

`define UMI_PORT(prefix, dw, cw, aw, i, o) \
    o wire prefix``_valid, \
    o wire [((cw)-1):0] prefix``_cmd, \
    o wire [((aw)-1):0] prefix``_dstaddr, \
    o wire [((aw)-1):0] prefix``_srcaddr, \
    o wire [((dw)-1):0] prefix``_data, \
    i wire prefix``_ready

`define UMI_INPUT(prefix, dw, cw, aw) \
    `UMI_PORT(prefix, dw, cw, aw, output, input)

`define UMI_OUTPUT(prefix, dw, cw, aw) \
    `UMI_PORT(prefix, dw, cw, aw, input, output)

`define UMI_PORT_ARRAY(prefix, dw, cw, aw, i, o, n) \
    o wire [((n)-1):0] prefix``_valid, \
    o wire [(((n)*(cw))-1):0] prefix``_cmd, \
    o wire [(((n)*(aw))-1):0] prefix``_dstaddr, \
    o wire [(((n)*(aw))-1):0] prefix``_srcaddr, \
    o wire [(((n)*(dw))-1):0] prefix``_data, \
    i wire [((n)-1):0] prefix``_ready

`define UMI_INPUT_ARRAY(prefix, dw, cw, aw, n) \
    `UMI_PORT_ARRAY(prefix, dw, cw, aw, output, input, n)

`define UMI_OUTPUT_ARRAY(prefix, dw, cw, aw, n) \
    `UMI_PORT_ARRAY(prefix, dw, cw, aw, input, output, n)

`define UMI_WIRES(prefix, dw, cw, aw) \
    wire prefix``_valid; \
    wire [((cw)-1):0] prefix``_cmd; \
    wire [((aw)-1):0] prefix``_dstaddr; \
    wire [((aw)-1):0] prefix``_srcaddr; \
    wire [((dw)-1):0] prefix``_data; \
    wire prefix``_ready

`define UMI_WIRES_ARRAY(prefix, dw, cw, aw, n) \
    wire [((n)-1):0] prefix``_valid; \
    wire [(((n)*(cw))-1):0] prefix``_cmd; \
    wire [(((n)*(aw))-1):0] prefix``_dstaddr; \
    wire [(((n)*(aw))-1):0] prefix``_srcaddr; \
    wire [(((n)*(dw))-1):0] prefix``_data; \
    wire [((n)-1):0] prefix``_ready

`define UMI_CONNECT(a, b) \
    .a``_valid(b``_valid), \
    .a``_cmd(b``_cmd), \
    .a``_dstaddr(b``_dstaddr), \
    .a``_srcaddr(b``_srcaddr), \
    .a``_data(b``_data), \
    .a``_ready(b``_ready)

`define UMI_CONNECT_SB(a) \
    .valid(a``_valid), \
    .cmd(a``_cmd), \
    .dstaddr(a``_dstaddr), \
    .srcaddr(a``_srcaddr), \
    .data(a``_data), \
    .ready(a``_ready)

`endif
