// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// systemverilog_synthesizer_configuration.dart
// Configuration for SystemVerilog synthesis.
//
// 2026 July 10
// Author: Max Korbel <max.korbel@intel.com>

/// Controls whether a type is included in a SystemVerilog port declaration.
enum SystemVerilogPortType {
  /// The type is included in the port declaration.
  explicit,

  /// The type is inferred according to SystemVerilog's defaults.
  implicit,
}

/// Configuration for SystemVerilog synthesis.
class SystemVerilogSynthesizerConfiguration {
  /// Whether SystemVerilog enum types and symbolic values are generated.
  final bool generateEnums;

  /// Whether port object types, such as `wire` and `var`, are explicit.
  final SystemVerilogPortType portObjectType;

  /// Whether port data types, such as `logic`, are explicit.
  final SystemVerilogPortType portDataType;

  /// Creates a new configuration for SystemVerilog synthesis.
  const SystemVerilogSynthesizerConfiguration({
    this.generateEnums = true,
    this.portObjectType = SystemVerilogPortType.explicit,
    this.portDataType = SystemVerilogPortType.explicit,
  });
}
