// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// schematic_gates.dart
// Schematic primitive descriptors for core gate modules.
//
// 2025 December 20
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/schematic/schematic_mixins.dart';

/// Registry of primitive descriptors for core ROHD gate modules.
///
/// This provides schematic synthesis support for core gates without modifying
/// their implementation. The descriptors are looked up by module type.
class CoreGatePrimitives {
  CoreGatePrimitives._() {
    _populateDefaults();
  }

  /// Singleton instance.
  static final CoreGatePrimitives instance = CoreGatePrimitives._();

  /// Map from runtime type to primitive descriptor.
  final Map<Type, PrimitiveDescriptor> _descriptors = {};

  /// Look up a primitive descriptor for a module by its runtime type.
  ///
  /// Returns `null` if no descriptor is registered for this type.
  PrimitiveDescriptor? lookupByType(Module m) => _descriptors[m.runtimeType];

  /// Register a primitive descriptor for a module type.
  void register(Type type, PrimitiveDescriptor descriptor) {
    _descriptors[type] = descriptor;
  }

  void _populateDefaults() {
    // Two-input gates
    register(
        And2Gate,
        const PrimitiveDescriptor(
          primitiveName: r'$and',
          portMap: {'A': 're:^in0_.+', 'B': 're:^in1_.+'},
          portDirs: {'A': 'input', 'B': 'input', 'Y': 'output'},
        ));
    register(
        Or2Gate,
        const PrimitiveDescriptor(
          primitiveName: r'$or',
          portMap: {'A': 're:^in0_.+', 'B': 're:^in1_.+'},
          portDirs: {'A': 'input', 'B': 'input', 'Y': 'output'},
        ));
    register(
        Xor2Gate,
        const PrimitiveDescriptor(
          primitiveName: r'$xor',
          portMap: {'A': 're:^in0_.+', 'B': 're:^in1_.+'},
          portDirs: {'A': 'input', 'B': 'input', 'Y': 'output'},
        ));

    // Single-input gates
    register(
        NotGate,
        const PrimitiveDescriptor(
          primitiveName: r'$not',
          portMap: {'A': 're:^in_.+'},
          portDirs: {'A': 'input', 'Y': 'output'},
        ));

    // Unary reduction gates
    register(
        AndUnary,
        const PrimitiveDescriptor(
          primitiveName: r'$logic_and',
          portDirs: {'A': 'input', 'Y': 'output'},
        ));
    register(
        OrUnary,
        const PrimitiveDescriptor(
          primitiveName: r'$logic_or',
          portDirs: {'A': 'input', 'Y': 'output'},
        ));
    register(
        XorUnary,
        const PrimitiveDescriptor(
          primitiveName: r'$xor',
          portDirs: {'A': 'input', 'Y': 'output'},
        ));

    // Comparison gates
    register(
        Equals,
        const PrimitiveDescriptor(
          primitiveName: r'$eq',
          portMap: {'A': 're:^_?in0_.+', 'B': 're:^_?in1_.+'},
          paramFromPort: {'A_WIDTH': 'A', 'B_WIDTH': 'B'},
          portDirs: {'A': 'input', 'B': 'input', 'Y': 'output'},
        ));
    register(
        NotEquals,
        const PrimitiveDescriptor(
          primitiveName: r'$ne',
          portMap: {'A': 're:^_?in0_.+', 'B': 're:^_?in1_.+'},
          paramFromPort: {'A_WIDTH': 'A', 'B_WIDTH': 'B'},
          portDirs: {'A': 'input', 'B': 'input', 'Y': 'output'},
        ));
    register(
        LessThan,
        const PrimitiveDescriptor(
          primitiveName: r'$lt',
          portMap: {'A': 're:^_?in0_.+', 'B': 're:^_?in1_.+'},
          paramFromPort: {'A_WIDTH': 'A', 'B_WIDTH': 'B'},
          portDirs: {'A': 'input', 'B': 'input', 'Y': 'output'},
        ));
    register(
        LessThanOrEqual,
        const PrimitiveDescriptor(
          primitiveName: r'$le',
          portMap: {'A': 're:^_?in0_.+', 'B': 're:^_?in1_.+'},
          paramFromPort: {'A_WIDTH': 'A', 'B_WIDTH': 'B'},
          portDirs: {'A': 'input', 'B': 'input', 'Y': 'output'},
        ));
    register(
        GreaterThan,
        const PrimitiveDescriptor(
          primitiveName: r'$gt',
          portMap: {'A': 're:^_?in0_.+', 'B': 're:^_?in1_.+'},
          paramFromPort: {'A_WIDTH': 'A', 'B_WIDTH': 'B'},
          portDirs: {'A': 'input', 'B': 'input', 'Y': 'output'},
        ));
    register(
        GreaterThanOrEqual,
        const PrimitiveDescriptor(
          primitiveName: r'$ge',
          portMap: {'A': 're:^_?in0_.+', 'B': 're:^_?in1_.+'},
          paramFromPort: {'A_WIDTH': 'A', 'B_WIDTH': 'B'},
          portDirs: {'A': 'input', 'B': 'input', 'Y': 'output'},
        ));

    // Shift operations
    register(
        LShift,
        const PrimitiveDescriptor(
          primitiveName: r'$shl',
          portMap: {'A': 're:^in_.+', 'B': 're:^shiftAmount_.+'},
          paramFromPort: {'A_WIDTH': 'A'},
          portDirs: {'A': 'input', 'B': 'input', 'Y': 'output'},
        ));
    register(
        RShift,
        const PrimitiveDescriptor(
          primitiveName: r'$shr',
          portMap: {'A': 're:^in_.+', 'B': 're:^shiftAmount_.+'},
          paramFromPort: {'A_WIDTH': 'A'},
          portDirs: {'A': 'input', 'B': 'input', 'Y': 'output'},
        ));
    register(
        ARShift,
        const PrimitiveDescriptor(
          primitiveName: r'$shiftx',
          portMap: {'A': 'A', 'B': 'B', 'Y': 'Y'},
          paramFromPort: {'A_WIDTH': 'A'},
          portDirs: {'A': 'input', 'B': 'input', 'Y': 'output'},
        ));

    // Bus operations
    register(
        Swizzle,
        const PrimitiveDescriptor(
          primitiveName: r'$concat',
          portMap: {
            'A': r're:^in\d+_.+',
            'B': r're:^in\d+_.+',
            'Y': r're:^(?:swizzled$|out$)'
          },
          portDirs: {'A': 'input', 'B': 'input', 'Y': 'output'},
        ));
    register(
        BusSubset,
        const PrimitiveDescriptor(
          primitiveName: r'$slice',
          portMap: {
            'A': r're:^in\d*_.+|^in_.+|^A$',
            'Y': r're:.*_subset_\d+_\d+|^out$'
          },
          paramFromPort: {'HIGH': 'A', 'LOW': 'A'},
          portDirs: {'A': 'input', 'Y': 'output'},
        ));

    // Mux
    register(
        Mux,
        const PrimitiveDescriptor(
          primitiveName: r'$mux',
          portMap: {
            'S':
                r're:^(?:_?control_.+|_?sel_.+|_?s_.+|in0_.+|in1_.+|A$|.*_subset_\d+_\d+)',
            'A': r're:^(?:d1_.+|B$|d1$|d1_.+)',
            'B': r're:^(?:d0_.+|C$|d0$|d0_.+)',
            'Y': r're:^(?:out$|Y$)'
          },
          paramFromPort: {'WIDTH': 'B'},
          portDirs: {'S': 'input', 'A': 'input', 'B': 'input', 'Y': 'output'},
        ));

    // Arithmetic with dynamic ports
    register(
        Add,
        const PrimitiveDescriptor(
          primitiveName: r'$add',
          useRawPortNames: true,
        ));

    // FlipFlop
    register(
        FlipFlop,
        const PrimitiveDescriptor(
          primitiveName: r'$dff',
          portMap: {
            'd': 'D',
            'q': 'Q',
            'clk': 'CLK',
            'en': 'EN',
            'reset': 'SRST'
          },
          portDirs: {
            'd': 'input',
            'q': 'output',
            'clk': 'input',
            'en': 'input',
            'reset': 'input'
          },
        ));

    // Combinational (special case)
    register(
        Combinational,
        const PrimitiveDescriptor(
          primitiveName: r'$combinational',
          useRawPortNames: true,
        ));
  }
}
