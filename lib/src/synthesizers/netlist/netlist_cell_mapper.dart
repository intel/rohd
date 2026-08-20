// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// netlist_cell_mapper.dart
// Maps selected ROHD modules to Yosys-primitive cell representations.
//
// 2026 February 11
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';

/// The result of mapping a netlist cell module to a Yosys-style cell.
@internal
typedef NetlistCellMapping = ({
  String cellType,
  Map<String, String> portDirs,
  Map<String, List<Object>> connections,
  Map<String, Object?> parameters,
});

/// Context provided to each netlist-cell mapping handler.
///
/// Contains the module instance plus the raw ROHD port directions and
/// connections built by the synthesizer, so handlers can remap them to
/// Yosys-primitive port names.
@internal
class NetlistCellContext {
  /// The ROHD [Module] being mapped.
  final Module module;

  /// Raw ROHD port-direction map (`{'portName': 'input'|'output'|'inout'}`).
  final Map<String, String> rawPortDirs;

  /// Raw ROHD connection map (`{'portName': [wireId, ...]}`).
  final Map<String, List<Object>> rawConns;

  /// Creates a [NetlistCellContext].
  const NetlistCellContext(this.module, this.rawPortDirs, this.rawConns);

  // ── Shared helper methods ───────────────────────────────────────────

  /// Find the first input port name matching [prefix].
  String? findInput(String prefix) {
    for (final k in module.inputs.keys) {
      if (k.startsWith(prefix)) {
        return k;
      }
    }
    return null;
  }

  /// The first output port name, or `null` if there are none.
  String? get firstOutput =>
      module.outputs.keys.isEmpty ? null : module.outputs.keys.first;

  /// The first input port name, or `null` if there are none.
  String? get firstInput =>
      module.inputs.keys.isEmpty ? null : module.inputs.keys.first;

  /// Width (number of wire IDs) for a given ROHD port name.
  int width(String portName) => rawConns[portName]?.length ?? 0;

  /// Build new port-direction and connection maps from a
  /// `{rohdPortName: yosysPortName}` mapping.
  ({Map<String, String> portDirs, Map<String, List<Object>> connections}) remap(
    Map<String, String> nameMap,
  ) {
    final pd = <String, String>{};
    final cn = <String, List<Object>>{};
    for (final e in nameMap.entries) {
      final rohdName = e.key;
      final netlistPortName = e.value;
      pd[netlistPortName] = rawPortDirs[rohdName] ?? 'output';
      cn[netlistPortName] = rawConns[rohdName] ?? [];
    }
    return (portDirs: pd, connections: cn);
  }
}

/// Signature for a netlist-cell mapping handler.
///
/// Returns a [NetlistCellMapping] if the handler recognises the module,
/// or `null` to let the next handler try.
@internal
typedef NetlistCellHandler = NetlistCellMapping? Function(
    NetlistCellContext ctx);

/// Maps modules already selected as netlist leaves to Yosys-primitive cell
/// representations.
///
/// Handlers are registered via [register] and tried in registration order.
/// Hierarchy stopping is controlled separately by [SynthModuleStopPolicy].
@internal
class NetlistCellMapper {
  /// Ordered list of registered handlers.
  final _handlers = <NetlistCellHandler>[];

  /// Creates an empty [NetlistCellMapper] with no registered handlers.
  NetlistCellMapper();

  /// Creates a mapper with all built-in ROHD netlist cell types registered.
  factory NetlistCellMapper.withDefaults() =>
      NetlistCellMapper().._registerDefaults();

  /// Register a mapping [handler].
  ///
  /// Handlers are tried in registration order; the first non-null result
  /// wins. Register more-specific handlers before less-specific ones.
  void register(NetlistCellHandler handler) {
    _handlers.add(handler);
  }

  /// Try to map [module] to a Yosys-primitive cell.
  ///
  /// Returns `null` if no registered handler matches.
  NetlistCellMapping? map(
    Module module,
    Map<String, String> rawPortDirs,
    Map<String, List<Object>> rawConns,
  ) {
    final ctx = NetlistCellContext(module, rawPortDirs, rawConns);
    for (final handler in _handlers) {
      final result = handler(ctx);
      if (result != null) {
        return result;
      }
    }
    return null;
  }

  // ══════════════════════════════════════════════════════════════════════
  //  Reusable mapping patterns
  // ══════════════════════════════════════════════════════════════════════

  /// Map a single-input, single-output gate (e.g. `$not`, `$reduce_and`).
  static NetlistCellMapping? unaryAY(NetlistCellContext ctx, String cellType) {
    final inN = ctx.firstInput;
    final out = ctx.firstOutput;
    if (inN == null || out == null) {
      return null;
    }
    final r = ctx.remap({inN: 'A', out: 'Y'});
    return (
      cellType: cellType,
      portDirs: r.portDirs,
      connections: r.connections,
      parameters: <String, Object?>{
        'A_WIDTH': ctx.width(inN),
        'Y_WIDTH': ctx.width(out),
      },
    );
  }

  /// Map a two-input gate with ports A, B, Y (e.g. `$and`, `$eq`, `$shl`).
  static NetlistCellMapping? binaryABY(
    NetlistCellContext ctx,
    String cellType, {
    required String inAPrefix,
    required String inBPrefix,
  }) {
    final a = ctx.findInput(inAPrefix);
    final b = ctx.findInput(inBPrefix);
    final out = ctx.firstOutput;
    if (a == null || b == null || out == null) {
      return null;
    }
    final r = ctx.remap({a: 'A', b: 'B', out: 'Y'});
    return (
      cellType: cellType,
      portDirs: r.portDirs,
      connections: r.connections,
      parameters: <String, Object?>{
        'A_WIDTH': ctx.width(a),
        'B_WIDTH': ctx.width(b),
        'Y_WIDTH': ctx.width(out),
      },
    );
  }

  /// Maps a shift gate to a Yosys binary shift cell.
  static NetlistCellMapping? shiftABY(
    NetlistCellContext ctx,
    String cellType, {
    required bool aSigned,
  }) {
    final a = ctx.findInput('_in');
    final b = ctx.findInput('_shiftAmount');
    final y = ctx.firstOutput;
    if (a == null || b == null || y == null) {
      return null;
    }
    final r = ctx.remap({a: 'A', b: 'B', y: 'Y'});
    return (
      cellType: cellType,
      portDirs: r.portDirs,
      connections: r.connections,
      parameters: <String, Object?>{
        'A_SIGNED': aSigned ? 1 : 0,
        'A_WIDTH': ctx.width(a),
        'B_SIGNED': 0,
        'B_WIDTH': ctx.width(b),
        'Y_WIDTH': ctx.width(y),
      },
    );
  }

  /// Map a two-input gate with ports A, B, Y (e.g. `$pow`, `$div`, `$mod`),
  /// including the standard Yosys `A_SIGNED`/`B_SIGNED` parameters.
  ///
  /// Unlike [binaryABY], this always emits the full standard parameter set
  /// (`A_SIGNED`, `A_WIDTH`, `B_SIGNED`, `B_WIDTH`, `Y_WIDTH`) so the result
  /// is directly consumable by standard Yosys tooling that expects these
  /// arithmetic cells to be fully specified.
  static NetlistCellMapping? binaryABYSigned(
    NetlistCellContext ctx,
    String cellType, {
    required String inAPrefix,
    required String inBPrefix,
    bool aSigned = false,
    bool bSigned = false,
  }) {
    final a = ctx.findInput(inAPrefix);
    final b = ctx.findInput(inBPrefix);
    final out = ctx.firstOutput;
    if (a == null || b == null || out == null) {
      return null;
    }
    final r = ctx.remap({a: 'A', b: 'B', out: 'Y'});
    return (
      cellType: cellType,
      portDirs: r.portDirs,
      connections: r.connections,
      parameters: <String, Object?>{
        'A_SIGNED': aSigned ? 1 : 0,
        'A_WIDTH': ctx.width(a),
        'B_SIGNED': bSigned ? 1 : 0,
        'B_WIDTH': ctx.width(b),
        'Y_WIDTH': ctx.width(out),
      },
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  //  Built-in handler registration
  // ══════════════════════════════════════════════════════════════════════

  /// Registers the built-in ROHD-to-Yosys primitive cell mappings.
  void _registerDefaults() {
    // Helper to reduce boilerplate for type-map-based handlers.
    void registerByTypeMap(
      Map<Type, String> typeMap,
      NetlistCellMapping? Function(NetlistCellContext ctx, String cellType)
          handler,
    ) {
      register((ctx) {
        final cellType = typeMap[ctx.module.runtimeType];
        return cellType == null ? null : handler(ctx, cellType);
      });
    }

    this
      // ── BusSubset → $slice ────────────────────────────────────────────
      ..register((ctx) {
        if (ctx.module is! BusSubset) {
          return null;
        }
        final sub = ctx.module as BusSubset;
        final inName = sub.inputs.keys.first;
        final outName = sub.outputs.keys.first;
        final r = ctx.remap({inName: 'A', outName: 'Y'});
        return (
          cellType: r'$slice',
          portDirs: r.portDirs,
          connections: r.connections,
          parameters: <String, Object?>{
            'OFFSET': sub.startIndex,
            'A_WIDTH': ctx.width(inName),
            'Y_WIDTH': ctx.width(outName),
          },
        );
      })
      // ── Swizzle → $concat ─────────────────────────────────────────────
      ..register((ctx) {
        if (ctx.module is! Swizzle) {
          return null;
        }
        final outName = ctx.firstOutput;
        final inputKeys = ctx.module.inputs.keys.toList();

        // Filter out zero-width inputs (degenerate concat operands).
        final nonZeroKeys = inputKeys.where((k) => ctx.width(k) > 0).toList();

        if (nonZeroKeys.length == 2 && outName != null) {
          final r = ctx.remap({
            nonZeroKeys[0]: 'A',
            nonZeroKeys[1]: 'B',
            outName: 'Y',
          });
          return (
            cellType: r'$concat',
            portDirs: r.portDirs,
            connections: r.connections,
            parameters: <String, Object?>{
              'A_WIDTH': ctx.width(nonZeroKeys[0]),
              'B_WIDTH': ctx.width(nonZeroKeys[1]),
            },
          );
        }

        // Single non-zero input ⇒ emit as $buf.
        if (nonZeroKeys.length == 1 && outName != null) {
          final r = ctx.remap({nonZeroKeys[0]: 'A', outName: 'Y'});
          return (
            cellType: r'$buf',
            portDirs: r.portDirs,
            connections: r.connections,
            parameters: <String, Object?>{'WIDTH': ctx.width(nonZeroKeys[0])},
          );
        }

        if (nonZeroKeys.isEmpty) {
          return null;
        }

        // N-input concat: per-input range labels, output is Y.
        final pd = <String, String>{};
        final cn = <String, List<Object>>{};
        final params = <String, Object?>{};
        var bitOffset = 0;
        for (var i = 0; i < nonZeroKeys.length; i++) {
          final ik = nonZeroKeys[i];
          final w = ctx.width(ik);
          final label =
              w == 1 ? '[$bitOffset]' : '[${bitOffset + w - 1}:$bitOffset]';
          pd[label] = 'input';
          cn[label] = ctx.rawConns[ik] ?? [];
          params['IN${i}_WIDTH'] = w;
          bitOffset += w;
        }
        if (outName != null) {
          pd['Y'] = 'output';
          cn['Y'] = ctx.rawConns[outName] ?? [];
        }
        return (
          cellType: r'$concat',
          portDirs: pd,
          connections: cn,
          parameters: params,
        );
      })
      // ── NOT gate ──────────────────────────────────────────────────────
      ..register((ctx) {
        if (ctx.module is! NotGate) {
          return null;
        }
        return unaryAY(ctx, r'$not');
      })
      // ── Mux ───────────────────────────────────────────────────────────
      ..register((ctx) {
        if (ctx.module is! Mux) {
          return null;
        }
        final ctrl = ctx.findInput('_control') ?? ctx.findInput('control');
        final d0 = ctx.findInput('_d0') ?? ctx.findInput('d0');
        final d1 = ctx.findInput('_d1') ?? ctx.findInput('d1');
        final out = ctx.firstOutput;
        if (ctrl == null || d0 == null || d1 == null || out == null) {
          return null;
        }
        // Yosys: S=select, A=d0 (when S=0), B=d1 (when S=1).
        final r = ctx.remap({ctrl: 'S', d0: 'A', d1: 'B', out: 'Y'});
        return (
          cellType: r'$mux',
          portDirs: r.portDirs,
          connections: r.connections,
          parameters: <String, Object?>{'WIDTH': ctx.width(d0)},
        );
      })
      // ── Add ───────────────────────────────────────────────────────────
      ..register((ctx) {
        if (ctx.module is! Add) {
          return null;
        }
        final in0 = ctx.findInput('_in0') ?? ctx.findInput('in0');
        final in1 = ctx.findInput('_in1') ?? ctx.findInput('in1');
        final sumName = ctx.module.outputs.keys.firstWhere(
          (k) => !k.contains('carry'),
          orElse: () => '',
        );
        final carryName = ctx.module.outputs.keys.firstWhere(
          (k) => k.contains('carry'),
          orElse: () => '',
        );
        if (in0 == null || in1 == null || sumName.isEmpty) {
          return null;
        }
        final pd = <String, String>{'A': 'input', 'B': 'input', 'Y': 'output'};
        final cn = <String, List<Object>>{
          'A': ctx.rawConns[in0] ?? [],
          'B': ctx.rawConns[in1] ?? [],
          'Y': ctx.rawConns[sumName] ?? [],
        };
        if (carryName.isNotEmpty) {
          pd['CO'] = 'output';
          cn['CO'] = ctx.rawConns[carryName] ?? [];
        }
        return (
          cellType: r'$add',
          portDirs: pd,
          connections: cn,
          parameters: <String, Object?>{
            'A_WIDTH': ctx.width(in0),
            'B_WIDTH': ctx.width(in1),
            'Y_WIDTH': ctx.width(sumName),
          },
        );
      })
      // ── FlipFlop → Yosys register cells ───────────────────────────────
      ..register((ctx) {
        final flipFlop = ctx.module;
        if (flipFlop is! FlipFlop) {
          return null;
        }
        final clk = ctx.findInput('_clk') ?? ctx.findInput('clk');
        final d = ctx.findInput('_d') ?? ctx.findInput('d');
        final en = ctx.findInput('_en') ?? ctx.findInput('en');
        final rst = ctx.findInput('_reset') ?? ctx.findInput('reset');
        final q = ctx.firstOutput;
        if (clk == null || d == null || q == null) {
          return null;
        }
        final hasEnable = en != null && ctx.rawConns.containsKey(en);
        final hasReset = rst != null && ctx.rawConns.containsKey(rst);
        final rstVal =
            ctx.findInput('_resetValue') ?? ctx.findInput('resetValue');
        final hasDynamicResetValue =
            hasReset && rstVal != null && ctx.rawConns.containsKey(rstVal);

        String cellType;
        if (!hasReset) {
          cellType = hasEnable ? r'$dffe' : r'$dff';
        } else if (flipFlop.asyncReset) {
          cellType = hasDynamicResetValue
              ? (hasEnable ? r'$aldffe' : r'$aldff')
              : (hasEnable ? r'$adffe' : r'$adff');
        } else if (!hasDynamicResetValue) {
          cellType = hasEnable ? r'$sdffe' : r'$sdff';
        } else {
          // Dynamic synchronous reset values are lowered to standard mux cells
          // by NetlistModuleTranslation.
          return null;
        }

        final pd = <String, String>{
          'CLK': 'input',
          'D': 'input',
          'Q': 'output',
        };
        final cn = <String, List<Object>>{
          'CLK': ctx.rawConns[clk] ?? [],
          'D': ctx.rawConns[d] ?? [],
          'Q': ctx.rawConns[q] ?? [],
        };
        if (hasEnable) {
          pd['EN'] = 'input';
          cn['EN'] = ctx.rawConns[en] ?? [];
        }
        if (hasReset) {
          final resetPort = flipFlop.asyncReset
              ? (hasDynamicResetValue ? 'ALOAD' : 'ARST')
              : 'SRST';
          pd[resetPort] = 'input';
          cn[resetPort] = ctx.rawConns[rst] ?? [];
        }
        if (hasDynamicResetValue) {
          pd['AD'] = 'input';
          cn['AD'] = ctx.rawConns[rstVal] ?? [];
        }

        final parameters = <String, Object?>{
          'WIDTH': ctx.width(d),
          'CLK_POLARITY': 1,
          if (hasEnable) 'EN_POLARITY': 1,
          if (hasReset && flipFlop.asyncReset)
            (hasDynamicResetValue ? 'ALOAD_POLARITY' : 'ARST_POLARITY'): 1,
          if (hasReset && !flipFlop.asyncReset) 'SRST_POLARITY': 1,
          if (hasReset && !hasDynamicResetValue)
            if (flipFlop.asyncReset)
              'ARST_VALUE':
                  flipFlop.constantResetValue!.toString(includeWidth: false)
            else
              'SRST_VALUE':
                  flipFlop.constantResetValue!.toString(includeWidth: false),
        };
        return (
          cellType: cellType,
          portDirs: pd,
          connections: cn,
          parameters: parameters,
        );
      });

    // ── Type-map-based gates ───────────────────────────────────────────
    final gateRegistrations = <(
      Map<Type, String>,
      NetlistCellMapping? Function(NetlistCellContext, String),
    )>[
      (
        const <Type, String>{
          And2Gate: r'$and',
          Or2Gate: r'$or',
          Xor2Gate: r'$xor',
        },
        (ctx, type) =>
            binaryABY(ctx, type, inAPrefix: '_in0', inBPrefix: '_in1'),
      ),
      (
        const <Type, String>{
          AndUnary: r'$reduce_and',
          OrUnary: r'$reduce_or',
          XorUnary: r'$reduce_xor',
        },
        unaryAY,
      ),
      (
        const <Type, String>{
          Multiply: r'$mul',
          Subtract: r'$sub',
          Equals: r'$eq',
          NotEquals: r'$ne',
          LessThan: r'$lt',
          GreaterThan: r'$gt',
          LessThanOrEqual: r'$le',
          GreaterThanOrEqual: r'$ge',
        },
        (ctx, type) =>
            binaryABY(ctx, type, inAPrefix: '_in0', inBPrefix: '_in1'),
      ),
      (
        const <Type, String>{LShift: r'$shl', RShift: r'$shr'},
        (ctx, type) => shiftABY(ctx, type, aSigned: false),
      ),
      (
        const <Type, String>{ARShift: r'$sshr'},
        (ctx, type) => shiftABY(ctx, type, aSigned: true),
      ),
      (
        const <Type, String>{
          Power: r'$pow',
          Divide: r'$div',
          Modulo: r'$mod',
        },
        (ctx, type) =>
            binaryABYSigned(ctx, type, inAPrefix: '_in0', inBPrefix: '_in1'),
      ),
    ];
    for (final (typeMap, handler) in gateRegistrations) {
      registerByTypeMap(typeMap, handler);
    }

    // ── IndexGate → $shiftx ─────────────────────────────────────────────
    //
    // `$shiftx` extracts `Y_WIDTH` bits of `A` starting at bit offset `B`,
    // producing `x` when the offset is out of range. This matches
    // [IndexGate]'s bit-select semantics (`original[index]`, `Y_WIDTH == 1`)
    // exactly, including its out-of-range-selects-`x` behavior.
    register((ctx) {
      if (ctx.module is! IndexGate) {
        return null;
      }
      final inputNames = ctx.module.inputs.keys.toList();
      if (inputNames.length != 2) {
        return null;
      }
      final a = inputNames[0];
      final b = inputNames[1];
      final y = ctx.firstOutput;
      if (y == null) {
        return null;
      }
      final r = ctx.remap({a: 'A', b: 'B', y: 'Y'});
      return (
        cellType: r'$shiftx',
        portDirs: r.portDirs,
        connections: r.connections,
        parameters: <String, Object?>{
          'A_SIGNED': 0,
          'A_WIDTH': ctx.width(a),
          'B_SIGNED': 0,
          'B_WIDTH': ctx.width(b),
          'Y_WIDTH': ctx.width(y),
        },
      );
    });

    // ── TriStateBuffer → $tribuf ──────────────────────────────────────
    register((ctx) {
      if (ctx.module is! TriStateBuffer) {
        return null;
      }
      final tsb = ctx.module as TriStateBuffer;
      final inName = tsb.inputs.keys.first; // data input
      final enName = tsb.inputs.keys.last; // enable
      final outName = tsb.inOuts.keys.first; // inout output
      final r = ctx.remap({inName: 'A', enName: 'EN', outName: 'Y'});
      r.portDirs['Y'] = 'output';
      return (
        cellType: r'$tribuf',
        portDirs: r.portDirs,
        connections: r.connections,
        parameters: <String, Object?>{'WIDTH': ctx.width(inName)},
      );
    });
  }
}
