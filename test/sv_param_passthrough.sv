// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// sv_param_passthrough.sv
// Module useful for testing parameter passthrough
//
// 2024 June 25
// Author: Max Korbel <max.korbel@intel.com>

module leaf_node #(
    parameter int A = 0,
    parameter int B = 0,
    parameter bit[3:0] C = 0,
    parameter logic D = 1'b0
) (
    input  logic [7:0] a,
    output logic [7:0] b
);

assign b = a + B;

endmodule : leaf_node
