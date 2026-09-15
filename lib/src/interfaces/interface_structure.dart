// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// interface_structure.dart
// A LogicStructure that represents a group of interface ports.
//
// 2026 May
// Author: ROHD Contributors

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';

/// A [LogicStructure] created from a group of [Interface] ports.
///
/// This enables [Interface] ports grouped by direction to be represented as
/// a single `typedef struct packed` in SystemVerilog, rather than individual
/// flat signals.
///
/// The [interfaceTypeName] is used to derive the SV typedef name when
/// generating struct-typed output.
@internal
class InterfaceStructure extends LogicStructure {
  /// The type name to use for the SV struct typedef, derived from the
  /// interface class name.
  final String interfaceTypeName;

  /// Creates an [InterfaceStructure] from a list of [Logic] elements.
  InterfaceStructure(
    super.elements, {
    required this.interfaceTypeName,
    super.name,
  });

  @override
  InterfaceStructure clone({String? name}) => InterfaceStructure(
        elements.map((e) => e.clone(name: e.name)),
        interfaceTypeName: interfaceTypeName,
        name: name ?? this.name,
      );
}
