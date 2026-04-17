// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// leaf_cell_mapper.dart
// Maps ROHD leaf modules to Yosys-primitive cell representations.
//
// 2026 February 11
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';

/// The result of mapping a leaf ROHD module to a Yosys-style cell.
typedef LeafCellMapping = ({
  String cellType,
  Map<String, String> portDirs,
  Map<String, List<Object>> connections,
  Map<String, Object?> parameters,
});

/// Context provided to each leaf-cell mapping handler.
///
/// Contains the module instance plus the raw ROHD port directions and
/// connections built by the synthesizer, so handlers can remap them to
/// Yosys-primitive port names.
class LeafCellContext {
  /// The ROHD [Module] being mapped.
  final Module module;

  /// Raw ROHD port-direction map (`{'portName': 'input'|'output'|'inout'}`).
  final Map<String, String> rawPortDirs;

  /// Raw ROHD connection map (`{'portName': [wireId, ...]}`).
  final Map<String, List<Object>> rawConns;

  /// Creates a [LeafCellContext].
  const LeafCellContext(this.module, this.rawPortDirs, this.rawConns);

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
  ({
    Map<String, String> portDirs,
    Map<String, List<Object>> connections,
  }) remap(Map<String, String> nameMap) {
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

/// Signature for a leaf-cell mapping handler.
///
/// Returns a [LeafCellMapping] if the handler recognises the module,
/// or `null` to let the next handler try.
typedef LeafCellHandler = LeafCellMapping? Function(LeafCellContext ctx);

/// Maps ROHD leaf [Module]s to Yosys-primitive cell representations.
///
/// Handlers are registered via [register] and tried in registration order.
/// A singleton instance with all built-in ROHD types pre-registered is
/// available via [LeafCellMapper.defaultMapper].
///
/// ```dart
/// final mapper = LeafCellMapper.defaultMapper;
/// final result = mapper.map(sub, rawPortDirs, rawConns);
/// ```
class LeafCellMapper {
  /// Ordered list of registered handlers.
  final _handlers = <LeafCellHandler>[];

  /// Creates an empty [LeafCellMapper] with no registered handlers.
  LeafCellMapper();

  /// The default mapper with all built-in ROHD leaf types registered.
  static final defaultMapper = LeafCellMapper._withDefaults();

  /// Register a mapping [handler].
  ///
  /// Handlers are tried in registration order; the first non-null result
  /// wins. Register more-specific handlers before less-specific ones.
  void register(LeafCellHandler handler) {
    _handlers.add(handler);
  }

  /// Try to map [module] to a Yosys-primitive cell.
  ///
  /// Returns `null` if no registered handler matches.
  LeafCellMapping? map(
    Module module,
    Map<String, String> rawPortDirs,
    Map<String, List<Object>> rawConns,
  ) {
    final ctx = LeafCellContext(module, rawPortDirs, rawConns);
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
  static LeafCellMapping? unaryAY(
    LeafCellContext ctx,
    String cellType,
  ) {
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
  static LeafCellMapping? binaryABY(
    LeafCellContext ctx,
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

  // ══════════════════════════════════════════════════════════════════════
  //  Built-in handler registration
  // ══════════════════════════════════════════════════════════════════════

  /// Creates a [LeafCellMapper] with built-in handlers for common ROHD leaf
  /// types.
  factory LeafCellMapper._withDefaults() {
    final m = LeafCellMapper();

    // Helper to reduce boilerplate for type-map-based handlers.
    void registerByTypeMap(
      Map<Type, String> typeMap,
      LeafCellMapping? Function(LeafCellContext ctx, String cellType) handler,
    ) {
      m.register((ctx) {
        final cellType = typeMap[ctx.module.runtimeType];
        return cellType == null ? null : handler(ctx, cellType);
      });
    }

    m
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
          final r = ctx
              .remap({nonZeroKeys[0]: 'A', nonZeroKeys[1]: 'B', outName: 'Y'});
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
            parameters: <String, Object?>{
              'WIDTH': ctx.width(nonZeroKeys[0]),
            },
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
          parameters: <String, Object?>{
            'WIDTH': ctx.width(d0),
          },
        );
      })

      // ── Add ───────────────────────────────────────────────────────────
      ..register((ctx) {
        if (ctx.module is! Add) {
          return null;
        }
        final in0 = ctx.findInput('_in0') ?? ctx.findInput('in0');
        final in1 = ctx.findInput('_in1') ?? ctx.findInput('in1');
        final sumName = ctx.module.outputs.keys
            .firstWhere((k) => !k.contains('carry'), orElse: () => '');
        final carryName = ctx.module.outputs.keys
            .firstWhere((k) => k.contains('carry'), orElse: () => '');
        if (in0 == null || in1 == null || sumName.isEmpty) {
          return null;
        }
        final pd = <String, String>{
          'A': 'input',
          'B': 'input',
          'Y': 'output',
        };
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

      // ── FlipFlop → $dff ───────────────────────────────────────────────
      ..register((ctx) {
        if (ctx.module is! FlipFlop) {
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
        final pd = <String, String>{
          '_clk': 'input',
          '_d': 'input',
          '_q': 'output',
        };
        final cn = <String, List<Object>>{
          '_clk': ctx.rawConns[clk] ?? [],
          '_d': ctx.rawConns[d] ?? [],
          '_q': ctx.rawConns[q] ?? [],
        };
        if (en != null && ctx.rawConns.containsKey(en)) {
          pd['_en'] = 'input';
          cn['_en'] = ctx.rawConns[en] ?? [];
        }
        if (rst != null && ctx.rawConns.containsKey(rst)) {
          pd['_reset'] = 'input';
          cn['_reset'] = ctx.rawConns[rst] ?? [];
        }
        final rstVal =
            ctx.findInput('_resetValue') ?? ctx.findInput('resetValue');
        if (rstVal != null && ctx.rawConns.containsKey(rstVal)) {
          pd['_resetValue'] = 'input';
          cn['_resetValue'] = ctx.rawConns[rstVal] ?? [];
        }
        return (
          cellType: r'$dff',
          portDirs: pd,
          connections: cn,
          parameters: <String, Object?>{
            'WIDTH': ctx.width(d),
            'CLK_POLARITY': 1,
          },
        );
      });

    // ── Type-map-based gates ───────────────────────────────────────────
    final gateRegistrations = <(
      Map<Type, String>,
      LeafCellMapping? Function(LeafCellContext, String),
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
        const <Type, String>{
          LShift: r'$shl',
          RShift: r'$shr',
          ARShift: r'$shiftx',
        },
        (ctx, type) =>
            binaryABY(ctx, type, inAPrefix: '_in', inBPrefix: '_shiftAmount'),
      ),
    ];
    for (final (typeMap, handler) in gateRegistrations) {
      registerByTypeMap(typeMap, handler);
    }

    // ── TriStateBuffer → $tribuf ──────────────────────────────────────
    m.register((ctx) {
      if (ctx.module is! TriStateBuffer) {
        return null;
      }
      final tsb = ctx.module as TriStateBuffer;
      final inName = tsb.inputs.keys.first; // data input
      final enName = tsb.inputs.keys.last; // enable
      final outName = tsb.inOuts.keys.first; // inout output
      final r = ctx.remap({inName: 'A', enName: 'EN', outName: 'Y'});
      return (
        cellType: r'$tribuf',
        portDirs: r.portDirs,
        connections: r.connections,
        parameters: <String, Object?>{
          'WIDTH': ctx.width(inName),
        },
      );
    });

    return m;
  }
}
