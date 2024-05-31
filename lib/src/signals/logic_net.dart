// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// logic_net.dart
// Definition for `LogicNet`.
//
// 2024 May 30
// Author: Max Korbel <max.korbel@intel.com>

part of 'signals.dart';

/// Represents a [Logic] which can be have multiple drivers, supporting
/// bidirectional signals.
class LogicNet extends Logic {
  @override
  Logic? get srcConnection => null;

  @override
  bool get isNet => true;

  /// Constructs a new [LogicNet] supporting multiple drivers named [name] with
  /// [width] bits.
  ///
  /// The default value for [width] is 1.  The [name] should be sanitary
  /// (variable rules for languages such as SystemVerilog).
  ///
  /// The [naming] and [name], if unspecified, are chosen based on the rules in
  /// [Naming.chooseNaming] and [Naming.chooseName], respectively.
  LogicNet({super.name, super.width, super.naming})
      : super._(wire: _WireNet(width: width));

  /// Constructs a new [LogicNet] with some additional validation for ports of
  /// [Module]s.
  ///
  /// Useful for [Interface] definitions.
  factory LogicNet.port(String name, [int width = 1]) {
    if (!Sanitizer.isSanitary(name)) {
      throw InvalidPortNameException(name);
    }

    return LogicNet(
      name: name,
      width: width,

      // make port names mergeable so we don't duplicate the ports
      // when calling connectIO
      naming: Naming.mergeable,
    );
  }

  @override
  void _connect(Logic other) {
    // if they are already connected, don't connect again!
    if (_srcConnections.contains(other)) {
      return;
    }

    if (other is LogicNet) {
      _updateWire(other._wire);
    } else {
      (_wire as _WireNet)._addDriver(other);
    }

    (_wire as _WireNet)._evaluateNewValue(signalName: name);

    if (other != this) {
      _srcConnections.add(other);
    }
  }

  @override
  String toString() => '${super.toString()}, [Net]';
}
