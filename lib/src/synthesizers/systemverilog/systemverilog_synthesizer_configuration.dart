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

/// Configuration for types in a SystemVerilog port declaration.
class SystemVerilogPortTypeConfiguration {
  /// Whether the object type, such as `wire` or `var`, is explicit.
  ///
  /// When an output port omits its object type but includes an explicit data
  /// type, SystemVerilog infers a variable. When both are omitted, it infers a
  /// net. See IEEE 1800-2023 section 23.2.2.3.
  final SystemVerilogPortType objectType;

  /// Whether the data type, such as `logic`, is explicit.
  final SystemVerilogPortType dataType;

  /// Creates a new configuration for types in a SystemVerilog port
  /// declaration.
  const SystemVerilogPortTypeConfiguration({
    this.objectType = SystemVerilogPortType.explicit,
    this.dataType = SystemVerilogPortType.explicit,
  });
}

/// Configuration for SystemVerilog synthesis.
class SystemVerilogSynthesizerConfiguration {
  /// Whether SystemVerilog enum types and symbolic values are generated.
  final bool generateEnums;

  /// Type configuration for input ports.
  final SystemVerilogPortTypeConfiguration inputPortType;

  /// Type configuration for output ports.
  final SystemVerilogPortTypeConfiguration outputPortType;

  /// Type configuration for inout ports.
  final SystemVerilogPortTypeConfiguration inOutPortType;

  /// Creates a new configuration for SystemVerilog synthesis.
  const SystemVerilogSynthesizerConfiguration({
    this.generateEnums = true,
    this.inputPortType = const SystemVerilogPortTypeConfiguration(
      objectType: SystemVerilogPortType.implicit,
    ),
    this.outputPortType = const SystemVerilogPortTypeConfiguration(
      objectType: SystemVerilogPortType.implicit,
    ),
    this.inOutPortType = const SystemVerilogPortTypeConfiguration(
      dataType: SystemVerilogPortType.implicit,
    ),
  });
}
