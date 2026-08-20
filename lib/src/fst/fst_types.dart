// Copyright (C) 2021-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// fst_types.dart
// Enumerations and constants for the FST (Fast Signal Trace) binary format.
//
// 2026 February
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

/// FST block types (from fstapi.h).
enum FstBlockType {
  /// File header.
  header(0),

  /// Value change data (zlib compressed).
  vcData(1),

  /// Blackout regions.
  blackout(2),

  /// Geometry (per-variable back-pointers for random access).
  geometry(3),

  /// Hierarchy (zlib compressed).
  hierarchy(4),

  /// Value changes with dynamic aliases (zlib).
  vcDataDynamicAlias(5),

  /// Hierarchy (LZ4 compressed).
  hierarchyLz4(6),

  /// Hierarchy (LZ4 double compressed).
  hierarchyLz4Duo(7),

  /// Value changes with dynamic aliases v2 (modern recommended format).
  vcDataDynamicAlias2(8),

  /// GZip wrapper.
  gzipWrapper(254),

  /// Skip/padding.
  skip(255);

  const FstBlockType(this.value);

  /// The numeric value of this block type as written in FST files.
  final int value;
}

/// FST scope types.
enum FstScopeType {
  /// A Verilog/SystemVerilog module instantiation scope.
  module(0),

  /// A Verilog/SystemVerilog task scope.
  task(1),

  /// A Verilog/SystemVerilog function scope.
  function_(2),

  /// A named `begin`..`end` block scope (Verilog).
  begin(3),

  /// A named `fork`..`join` block scope (Verilog).
  fork(4),

  /// A `generate` block scope (SystemVerilog).
  generate(5),

  /// A `struct` type scope (SystemVerilog).
  struct_(6),

  /// A `union` type scope (SystemVerilog).
  union(7),

  /// A `class` scope (SystemVerilog).
  class_(8),

  /// An `interface` scope (SystemVerilog).
  interface(9),

  /// A `package` scope (SystemVerilog).
  package(10),

  /// A `program` scope (SystemVerilog).
  program(11);

  const FstScopeType(this.value);

  /// The numeric value of this scope type as written in FST files.
  final int value;
}

/// FST variable types.
enum FstVarType {
  /// An event variable.
  event(0),

  /// A Verilog `integer` variable (32-bit, 4-state).
  integer(1),

  /// A Verilog `parameter` or `localparam`.
  parameter(2),

  /// A `real` variable (double-precision floating point).
  real(3),

  /// A `real` parameter.
  realParameter(4),

  /// A `reg` variable (Verilog 4-state storage).
  reg(5),

  /// A `supply0` net (logic-0 power supply).
  supply0(6),

  /// A `supply1` net (logic-1 power supply).
  supply1(7),

  /// A `time` variable.
  time(8),

  /// A `tri` net (tri-state, same resolution as `wire`).
  tri(9),

  /// A `triand` net (tri-state with wired-AND resolution).
  triAnd(10),

  /// A `trior` net (tri-state with wired-OR resolution).
  triOr(11),

  /// A `trireg` net (retains last driven value when undriven).
  triReg(12),

  /// A `tri0` net (pulls to 0 when undriven).
  tri0(13),

  /// A `tri1` net (pulls to 1 when undriven).
  tri1(14),

  /// A `wand` net (wired-AND).
  wand(15),

  /// A `wire` net (standard Verilog interconnect).
  wire(16),

  /// A `wor` net (wired-OR).
  wor(17),

  /// A port variable.
  port(18),

  /// A sparse array variable.
  sparseArray(19),

  /// A `realtime` variable.
  realTime(20),

  /// A generic string variable.
  genericString(21),

  // SystemVerilog types

  /// A SystemVerilog `bit` type (2-state, unsigned).
  bit(22),

  /// A SystemVerilog `logic` type (4-state).
  logic(23),

  /// A SystemVerilog `int` type (32-bit, 2-state, signed).
  int_(24),

  /// A SystemVerilog `shortint` type (16-bit, 2-state, signed).
  shortInt(25),

  /// A SystemVerilog `longint` type (64-bit, 2-state, signed).
  longInt(26),

  /// A SystemVerilog `byte` type (8-bit, 2-state, signed).
  byte_(27),

  /// A SystemVerilog `enum` type.
  enum_(28),

  /// A SystemVerilog `shortreal` type (single-precision float).
  shortReal(29);

  const FstVarType(this.value);

  /// The numeric value of this variable type as written in FST files.
  final int value;
}

/// FST variable direction.
enum FstVarDirection {
  /// No direction specified (implicit net).
  implicit(0),

  /// Input port.
  input(1),

  /// Output port.
  output(2),

  /// Bidirectional (inout) port.
  inout(3),

  /// Buffer port (output that can be read back).
  buffer(4),

  /// Linkage port (VHDL linkage mode).
  linkage(5);

  const FstVarDirection(this.value);

  /// The numeric value of this direction as written in FST files.
  final int value;
}

/// FST file type.
enum FstFileType {
  /// Verilog source.
  verilog(0),

  /// VHDL source.
  vhdl(1),

  /// Mixed Verilog and VHDL source.
  verilogVhdl(2);

  const FstFileType(this.value);

  /// The numeric value of this file type as written in FST files.
  final int value;
}
