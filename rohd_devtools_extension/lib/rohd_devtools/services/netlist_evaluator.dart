// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// netlist_evaluator.dart
// Evaluates signal values from Yosys JSON netlist on a per-module basis.
//
// All evaluation operates within a single Yosys module definition at a time.
// Keys in internal maps are LOCAL signal/port names (not full hierarchy paths).
// Module index structures are cached per definition name so all instances of
// the same module type share one index.
//
// 2026 March
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:rohd/rohd.dart' show LogicValue;
import 'package:rohd_devtools_extension/rohd_devtools/utils/regex_utils.dart';

/// Matches array element netnames of the form `parent_N_`.
///
/// Group 1: parent signal name (e.g. `data_0__0_`)
/// Group 2: element index (e.g. `0`)
const _arrayElementPattern = r'^(.+)_(\d+)_$';

// Yosys cell type → evaluable op name
// ---------------------------------------------------------------------------
const _cellTypeToOp = <String, String>{
  r'$and': 'and',
  r'$or': 'or',
  r'$xor': 'xor',
  r'$not': 'not',
  r'$buf': 'buf',
  r'$mux': 'mux',
  r'$reduce_or': 'uor',
  r'$reduce_and': 'uand',
  r'$reduce_xor': 'uxor',
  r'$reduce_bool': 'uor', // same as $reduce_or for evaluation
  r'$eq': 'eq',
  r'$ne': 'ne',
  r'$shl': 'sll',
  r'$shr': 'srl',
  r'$sshl': 'sll', // signed same bit-ops for unsigned eval
  r'$sshr': 'ssrl',
  r'$ge': 'gte',
  r'$gt': 'gt',
  r'$le': 'le',
  r'$lt': 'lt',
  r'$add': 'add',
  r'$sub': 'sub',
  r'$mul': 'mul',
  r'$neg': 'neg',
  r'$pos': 'buf', // $pos is identity
  r'$logic_not': 'lnot',
  r'$logic_and': 'land',
  r'$logic_or': 'lor',
  // $concat, $slice, $struct_field, $struct_compose, $struct_unpack,
  // $struct_pack, $const, $dff handled specially.
};

// ---------------------------------------------------------------------------
// Shared helpers — single source of truth for top-key lookup, index
// caching, stale-cache detection, and path resolution.
// ---------------------------------------------------------------------------

/// Find the module definition marked `top`, or fall back to the first key.
String? _findTopKey(Map<String, dynamic> modules) {
  for (final e in modules.entries) {
    final attrs = (e.value as Map<String, dynamic>)['attributes']
        as Map<String, dynamic>?;
    if (attrs?['top'] == 1) {
      return e.key;
    }
  }
  return modules.keys.isNotEmpty ? modules.keys.first : null;
}

/// Retrieve or build the [_ModuleIndex] for [moduleKey], applying a
/// stale-cache guard so that a slim→full module upgrade is detected
/// automatically.
_ModuleIndex _getOrBuildIndex(
  Map<String, dynamic> modData,
  Map<String, dynamic> cells,
  String moduleKey,
  EvalOnDemandCache? cache,
) {
  var idx =
      cache?._moduleIndices[moduleKey] ?? _buildModuleIndex(modData, cells);
  // Stale-cache guard: if the cached index has no drivers but cells now
  // have port_directions (module was upgraded from slim → full since the
  // index was built), rebuild the index.
  if (idx.driverOf.isEmpty && cells.isNotEmpty) {
    final firstCell = cells.values.first as Map<String, dynamic>;
    if (firstCell.containsKey('port_directions')) {
      idx = _buildModuleIndex(modData, cells);
      cache?._moduleIndices[moduleKey] = idx;
    }
  }
  cache?._moduleIndices[moduleKey] ??= idx;
  return idx;
}

/// Walk a split signal path through the module hierarchy, returning the
/// resolved module definition, instance path, and cached index.
///
/// Returns `null` when the path cannot be resolved (missing module, missing
/// cell, cell type not in [modules], etc.).
///
/// When a `$const` cell is encountered during the walk the parsed constant
/// value is returned via [constResult] (if non-null) so that callers can
/// short-circuit without a separate path walk.
_ResolvedModule? _resolveModulePath(
  Map<String, dynamic> modules,
  List<String> parts,
  EvalOnDemandCache? cache, {
  _Box<({String value, int width})?>? constResult,
}) {
  final topKey = _findTopKey(modules);
  if (topKey == null) {
    return null;
  }
  var moduleKey = topKey;
  var instancePath = parts[0];
  for (var i = 1; i < parts.length - 1; i++) {
    final cellName = parts[i];
    final modData = modules[moduleKey] as Map<String, dynamic>?;
    if (modData == null) {
      return null;
    }
    final cells = modData['cells'] as Map<String, dynamic>? ?? {};
    final cell = cells[cellName] as Map<String, dynamic>?;
    if (cell == null) {
      return null;
    }
    final nextType = cell['type'] as String?;
    // $const cell: the output port name IS the Verilog constant literal.
    if (nextType == r'$const' && constResult != null) {
      try {
        final lv = LogicValue.ofRadixString(parts.last);
        constResult.value = (value: lv.toString(), width: lv.width);
      } on Object {
        constResult.value = null;
      }
      return null;
    }
    if (nextType == null || !modules.containsKey(nextType)) {
      return null;
    }
    moduleKey = nextType;
    // Repeated concatenation is clearer here because each segment is retained.
    // ignore: use_string_buffers
    instancePath = '$instancePath/$cellName';
  }
  final modData = modules[moduleKey] as Map<String, dynamic>?;
  if (modData == null) {
    return null;
  }
  final cells = modData['cells'] as Map<String, dynamic>? ?? {};
  final idx = _getOrBuildIndex(modData, cells, moduleKey, cache);
  return _ResolvedModule(
    moduleKey: moduleKey,
    instancePath: instancePath,
    index: idx,
  );
}

/// Tiny mutable box for returning a secondary result from [_resolveModulePath].
class _Box<T> {
  T value;
  _Box(this.value);
}

// ---------------------------------------------------------------------------
// Per-module index
// ---------------------------------------------------------------------------

/// Per-module index structures cached across evaluation calls.
class _ModuleIndex {
  final Map<int, String> bitToSig;
  final Map<String, List<int>> sigBits;
  final Map<String, Map<int, int>> bitIndexInSig;
  final Map<String, Map<String, dynamic>> driverOf;
  final Map<String, dynamic> ports;
  final Map<String, dynamic> netnames;
  final Map<String, dynamic> cells;

  _ModuleIndex({
    required this.bitToSig,
    required this.sigBits,
    required this.bitIndexInSig,
    required this.driverOf,
    required this.ports,
    required this.netnames,
    required this.cells,
  });
}

// ---------------------------------------------------------------------------
// On-demand evaluation cache
// ---------------------------------------------------------------------------

/// Cross-call cache for signal evaluation.
///
/// Holds per-module index structures and resolved signal values so that
/// evaluating many signals in the same module doesn't rebuild index maps
/// or re-evaluate shared sub-expressions.
///
/// Create a fresh instance for each snapshot time (or call [clear] when
/// the snapshot changes).
class EvalOnDemandCache {
  final Map<String, _ModuleIndex> _moduleIndices;
  final _resolvedValues = <String, LogicValue>{};

  /// Creates a new, empty cache.
  EvalOnDemandCache() : _moduleIndices = {};

  /// Internal: shares `_moduleIndices` reference from the parent cache.
  EvalOnDemandCache._shared(this._moduleIndices);

  /// Create a lightweight cache that shares the structural (module index)
  /// data with this instance but has its own resolved-value store.
  ///
  /// Use this for time-series evaluation (waveform synthesis) where
  /// resolved values change at each timepoint and must not pollute
  /// the point-in-time cache used by hover / details pane.
  EvalOnDemandCache withSharedStructure() =>
      EvalOnDemandCache._shared(_moduleIndices);

  /// Clear resolved values (e.g. when snapshot time changes).
  ///
  /// Module indices are kept for performance.  If a module is upgraded
  /// from slim to full between calls, the stale-cache guard in
  /// [_getOrBuildIndex] will detect the mismatch and rebuild.
  void clear() {
    _resolvedValues.clear();
  }

  /// Full reset — also discards module indices (e.g. after hierarchy reload).
  void reset() {
    _moduleIndices.clear();
    _resolvedValues.clear();
  }
}

// ---------------------------------------------------------------------------
// NetlistEvaluator — thin wrapper around per-module evaluation
// ---------------------------------------------------------------------------

/// Evaluates computed signal values from a Yosys JSON netlist.
///
/// All evaluation operates per-module using [evaluateSignalOnDemand].
/// Module index structures ([_ModuleIndex]) are built lazily and cached
/// per definition name, so all instances of the same module type share
/// one index — no O(total signals) path expansion.
class NetlistEvaluator {
  /// Module definitions: `{ moduleName: moduleData }`.
  final Map<String, dynamic> _modules;

  /// Shared cache for module index structures and resolved values.
  final EvalOnDemandCache _cache;

  /// Creates an evaluator for the given Yosys module definitions.
  ///
  /// `modules` is the `modules` section of a Yosys JSON netlist.
  /// `cache` is an optional shared cache; a new one is created if omitted.
  NetlistEvaluator(this._modules, [EvalOnDemandCache? cache])
      : _cache = cache ?? EvalOnDemandCache();

  /// The shared cache (exposed for callers that need
  /// [EvalOnDemandCache.withSharedStructure]).
  EvalOnDemandCache get cache => _cache;

  /// Evaluate a single signal and return its value as a formatted string.
  ({String value, int width})? evaluate(
    String rerootedPath,
    String? Function(String fullPath) snapshotLookup,
  ) =>
      evaluateSignalOnDemand(
        modules: _modules,
        rerootedPath: rerootedPath,
        snapshotLookup: snapshotLookup,
        evalCache: _cache,
      );

  /// Evaluate multiple signals, returning a map of signalPath -> LogicValue.
  Map<String, LogicValue> evaluateBatch(
    Iterable<String> signalPaths,
    String? Function(String fullPath) snapshotLookup,
  ) {
    final results = <String, LogicValue>{};
    for (final path in signalPaths) {
      final r = evaluateSignalOnDemand(
        modules: _modules,
        rerootedPath: path,
        snapshotLookup: snapshotLookup,
        evalCache: _cache,
      );
      if (r != null) {
        results[path] = parseHexToLV(r.value, r.width);
      } else if (path.contains('const_31')) {
        debugPrint(
          '[CONST-DBG] evaluateSignalOnDemand returned NULL '
          'for: $path',
        );
      }
    }
    return results;
  }

  /// Collect tracked leaf signal IDs that [signalPath] depends on.
  Set<String> collectLeaves(String signalPath) {
    final parts = signalPath.split('/');
    if (parts.length < 2) {
      return {};
    }
    final resolved = _resolveModulePath(_modules, parts, _cache);
    if (resolved == null) {
      return {};
    }
    final idx = resolved.index;
    final instancePath = resolved.instancePath;
    final signalName = parts.last;
    final leaves = <String>{};
    final visited = <String>{};

    void walk(String name) {
      if (visited.contains(name)) {
        return;
      }
      visited.add(name);
      final driver = idx.driverOf[name];
      if (driver == null) {
        // No cell driver.  Check if this is a connection net whose bits
        // trace to another named signal (wire alias).  If so, walk the
        // source signal(s) instead of treating self as a leaf — otherwise
        // we'd request waveform data for the alias itself, which the
        // server doesn't track.
        final bits = idx.sigBits[name];
        if (bits != null) {
          var foundAlias = false;
          for (final b in bits) {
            final traceSig = idx.bitToSig[b];
            if (traceSig != null && traceSig != name) {
              walk(traceSig);
              foundAlias = true;
            }
          }
          if (foundAlias) {
            return;
          }
        }
        // Array element: walk the parent signal's leaves.
        final arrayMatch = regExpFirstMatch(_arrayElementPattern, name);
        if (arrayMatch != null) {
          final parentName = arrayMatch.group(1)!;
          if (idx.sigBits.containsKey(parentName)) {
            walk(parentName);
            return;
          }
        }
        leaves.add('$instancePath/$name');
        return;
      }
      final ct = driver['type']?.toString() ?? '';
      final conns = driver['connections'] as Map<String, dynamic>? ?? {};
      final pDirs = driver['port_directions'] as Map<String, dynamic>? ?? {};

      if (ct == r'$dff') {
        // The DFF output netname (e.g. `_q`) is a synthesizer-generated
        // connection net — not directly tracked by the server.  The
        // tracked signal lives at the cell-level path:
        //   $instancePath/$cellName/$outputPort
        // This mirrors the evaluate() $dff handler which looks up
        // snapshotLookup('$instancePath/$cellName/$pn').
        String? cellName;
        for (final ce in idx.cells.entries) {
          if (identical(ce.value, driver)) {
            cellName = ce.key;
            break;
          }
        }
        if (cellName != null) {
          final targetBits = idx.sigBits[name] ?? [];
          for (final pn in pDirs.keys) {
            if (pDirs[pn] != 'output') {
              continue;
            }
            final outBits = conns[pn] as List? ?? [];
            final outBitSet = outBits.whereType<int>().toSet();
            if (targetBits.isNotEmpty && targetBits.every(outBitSet.contains)) {
              leaves.add('$instancePath/$cellName/$pn');
              return;
            }
          }
        }
        leaves.add('$instancePath/$name');
        return;
      }
      if (ct == r'$const') {
        return;
      }
      if (!ct.startsWith(r'$') || !_cellTypeToOp.containsKey(ct)) {
        if (ct != r'$concat' &&
            ct != r'$slice' &&
            ct != r'$struct_field' &&
            ct != r'$struct_compose' &&
            ct != r'$struct_unpack' &&
            ct != r'$struct_pack') {
          // Sub-module cell: the leaf is the submodule's output port
          // that drives this signal, not the parent-level connection net.
          if (_modules.containsKey(ct)) {
            String? cellName;
            for (final ce in idx.cells.entries) {
              if (identical(ce.value, driver)) {
                cellName = ce.key;
                break;
              }
            }
            if (cellName != null) {
              final targetBits = idx.sigBits[name] ?? [];
              for (final pn in pDirs.keys) {
                if (pDirs[pn] != 'output') {
                  continue;
                }
                final outBits = conns[pn] as List? ?? [];
                final outBitSet = outBits.whereType<int>().toSet();
                if (targetBits.every(outBitSet.contains)) {
                  leaves.add('$instancePath/$cellName/$pn');
                  return;
                }
              }
            }
          }
          leaves.add('$instancePath/$name');
          return;
        }
      }
      for (final pName in pDirs.keys) {
        if (pDirs[pName] == 'output') {
          continue;
        }
        final bits = conns[pName] as List? ?? [];
        for (final b in bits) {
          if (b is int) {
            final sig = idx.bitToSig[b];
            if (sig != null) {
              walk(sig);
            }
          }
        }
      }
    }

    walk(signalName);
    return leaves;
  }

  /// Whether the given signal can be evaluated locally.
  ///
  /// Returns true when:
  ///  - a cell drives it (`driverOf` has an entry), or
  ///  - it names a `$const` cell, or
  ///  - it is a netname/port whose bits trace to other signals in the
  ///    same module (connection net / wire alias).
  bool isComputed(String signalPath) {
    final parts = signalPath.split('/');
    if (parts.length < 2) {
      return false;
    }
    final resolved = _resolveModulePath(_modules, parts, _cache);
    if (resolved == null) {
      return false;
    }
    final signalName = parts.last;
    if (resolved.index.driverOf.containsKey(signalName)) {
      return true;
    }
    final cell = resolved.index.cells[signalName] as Map<String, dynamic>?;
    if (cell != null && cell['type'] == r'$const') {
      return true;
    }
    // Connection net: a netname (or port) whose bits trace to other
    // named signals via the bit-connectivity graph.  These are wires
    // the synthesizer created to connect parent ports to submodule ports.
    final bits = resolved.index.sigBits[signalName];
    if (bits != null && bits.isNotEmpty) {
      for (final b in bits) {
        final traceSig = resolved.index.bitToSig[b];
        if (traceSig != null && traceSig != signalName) {
          return true;
        }
      }
    }
    // Array element: name matches `parent_N_` and parent exists.
    final arrayMatch = regExpFirstMatch(_arrayElementPattern, signalName);
    if (arrayMatch != null) {
      final parentName = arrayMatch.group(1)!;
      if (resolved.index.sigBits.containsKey(parentName)) {
        return true;
      }
    }
    return false;
  }

  /// Whether the signal's containing module can be resolved and has
  /// full connectivity data (not slim, not a primitive cell path).
  ///
  /// Use this as a cheap pre-filter before batch evaluation to avoid
  /// feeding signals that will always BAIL.
  bool canEvaluate(String signalPath) {
    final parts = signalPath.split('/');
    if (parts.length < 2) {
      return false;
    }
    final resolved = _resolveModulePath(_modules, parts, _cache);
    if (resolved == null) {
      return false;
    }
    // Check for slim modules (cells exist but lack connections).
    final cells = resolved.index.cells;
    if (cells.isNotEmpty) {
      final firstCell = cells.values.first as Map<String, dynamic>;
      if (!firstCell.containsKey('connections')) {
        // Even in slim modules, array sub-elements can be resolved
        // from the parent port's snapshot value.
        final signalName = parts.last;
        final arrayMatch = regExpFirstMatch(_arrayElementPattern, signalName);
        if (arrayMatch != null) {
          final parentName = arrayMatch.group(1)!;
          if (resolved.index.sigBits.containsKey(parentName)) {
            return true;
          }
        }
        return false;
      }
    }
    return true;
  }

  /// Get signal width from its containing module's metadata.
  int signalWidth(String signalPath) {
    final parts = signalPath.split('/');
    if (parts.length < 2) {
      return 0;
    }
    final resolved = _resolveModulePath(_modules, parts, _cache);
    if (resolved == null) {
      return 0;
    }
    final signalName = parts.last;
    final nnData = resolved.index.netnames[signalName] as Map<String, dynamic>?;
    if (nnData != null) {
      return (nnData['bits'] as List?)?.whereType<int>().length ?? 1;
    }
    final pData = resolved.index.ports[signalName] as Map<String, dynamic>?;
    if (pData != null) {
      return (pData['bits'] as List?)?.whereType<int>().length ?? 1;
    }
    return 0;
  }

  /// Enumerate all evaluable signal paths under [rootInstance].
  ///
  /// Walks the module hierarchy recursively, collecting netname signals
  /// that have driver cells (computed signals not already tracked as ports).
  /// Returns full paths like `rootInstance/signal` or
  /// `rootInstance/subcell/signal`.
  ///
  /// This discovers signals that exist in the netlist but are absent from
  /// the hierarchy tree (e.g. structure field extractions like `a_mantissa`).
  Set<String> allEvaluablePaths(String rootInstance) {
    final result = <String>{};
    final topKey = _findTopKey(_modules);
    if (topKey == null) {
      return result;
    }
    _collectEvaluablePaths(topKey, rootInstance, result);
    return result;
  }

  void _collectEvaluablePaths(
    String moduleKey,
    String instancePath,
    Set<String> result,
  ) {
    final modData = _modules[moduleKey] as Map<String, dynamic>?;
    if (modData == null) {
      return;
    }
    final cells = modData['cells'] as Map<String, dynamic>? ?? {};

    // Skip slim modules (cells without connections).
    if (cells.isNotEmpty) {
      final firstCell = cells.values.first as Map<String, dynamic>;
      if (!firstCell.containsKey('connections')) {
        return;
      }
    }

    final idx = _getOrBuildIndex(modData, cells, moduleKey, _cache);

    // Add netnames that have driver cells (computed signals)
    // and array sub-element netnames whose parent is resolvable.
    for (final name in idx.netnames.keys) {
      if (idx.driverOf.containsKey(name)) {
        result.add('$instancePath/$name');
        continue;
      }
      // Array element: include if parent exists in this module.
      final arrayMatch = regExpFirstMatch(_arrayElementPattern, name);
      if (arrayMatch != null) {
        final parentName = arrayMatch.group(1)!;
        if (idx.sigBits.containsKey(parentName)) {
          result.add('$instancePath/$name');
        }
      }
    }

    // Recurse into sub-module cells.
    for (final cellEntry in cells.entries) {
      final cellData = cellEntry.value as Map<String, dynamic>;
      final cellType = cellData['type'] as String?;
      if (cellType != null && _modules.containsKey(cellType)) {
        _collectEvaluablePaths(
          cellType,
          '$instancePath/${cellEntry.key}',
          result,
        );
      }
    }
  }

  /// Clear all resolved values from the cache.
  void clearValues() => _cache.clear();

  /// Reset the cache (clears resolved values and module indices).
  void reset() => _cache.reset();
}

class _ResolvedModule {
  final String moduleKey;
  final String instancePath;
  final _ModuleIndex index;
  _ResolvedModule({
    required this.moduleKey,
    required this.instancePath,
    required this.index,
  });
}

// ---------------------------------------------------------------------------
// evaluateSignalOnDemand
// ---------------------------------------------------------------------------

/// Evaluate a single signal on-demand within one Yosys module definition.
///
/// Given the full `modules` map, a re-rooted signal path, and a function
/// that looks up snapshot values, traces backwards through cells in the
/// signal's immediate module definition until it hits tracked values (ports
/// or snapshot entries), then evaluates forward.
///
/// Works within a **single level of hierarchy** — never expands into
/// sub-module definitions.  Ports are assumed to have values in the snapshot.
///
/// Returns `(value, width)` or `null` if the signal can't be evaluated.
({String value, int width})? evaluateSignalOnDemand({
  required Map<String, dynamic> modules,
  required String rerootedPath,
  required String? Function(String fullPath) snapshotLookup,
  EvalOnDemandCache? evalCache,
}) {
  final parts = rerootedPath.split('/');
  if (parts.length < 2) {
    return null;
  }

  // Resolve path through the hierarchy.  The constResult box lets us
  // short-circuit when a $const cell is encountered during the walk.
  // ignore: no_leading_underscores_for_local_identifiers
  final _isConstDbg = rerootedPath.contains('const_31');
  final constBox = _Box<({String value, int width})?>(null);
  final resolved = _resolveModulePath(
    modules,
    parts,
    evalCache,
    constResult: constBox,
  );
  if (constBox.value != null) {
    if (_isConstDbg) {
      debugPrint(
        '[CONST-DBG] $rerootedPath: constBox shortcut => '
        '${constBox.value}',
      );
    }
    return constBox.value;
  }
  if (resolved == null) {
    if (_isConstDbg) {
      debugPrint(
        '[CONST-DBG] $rerootedPath: _resolveModulePath returned NULL '
        '(parts=$parts)',
      );
    }
    return null;
  }

  final signalName = parts.last;
  final instancePath = resolved.instancePath;
  final idx = resolved.index;
  final cells = idx.cells;

  // ── Lightweight snapshot-only resolution ──────────────────────────
  // For port-level signals (including array sub-elements), we can
  // resolve values directly from the snapshot without needing full
  // module connectivity.  This avoids bailing on slim modules for
  // signals that are purely port decompositions.
  final sigBits = idx.sigBits;

  // Determine signal width from netnames/ports metadata.
  int targetWidthOf(String name) {
    final nnData = idx.netnames[name] as Map<String, dynamic>?;
    if (nnData != null) {
      return (nnData['bits'] as List?)?.whereType<int>().length ?? 1;
    }
    final pData = idx.ports[name] as Map<String, dynamic>?;
    if (pData != null) {
      return (pData['bits'] as List?)?.whereType<int>().length ?? 1;
    }
    return 0;
  }

  // Try resolving from snapshot: direct lookup or array element slicing.
  LogicValue? resolveFromSnapshot(String name, int fw) {
    // Direct snapshot match.
    final fullPath = '$instancePath/$name';
    final snapVal = snapshotLookup(fullPath);
    if (snapVal != null) {
      return parseHexToLV(snapVal, fw);
    }
    // Array element pattern: resolve parent from snapshot recursively.
    final m = regExpFirstMatch(_arrayElementPattern, name);
    if (m != null) {
      final parentName = m.group(1)!;
      final elementIndex = int.parse(m.group(2)!);
      final parentBits = sigBits[parentName];
      if (parentBits != null && parentBits.isNotEmpty) {
        final parentWidth = parentBits.length;
        final offset = elementIndex * fw;
        if (offset + fw <= parentWidth) {
          final parentVal = resolveFromSnapshot(parentName, parentWidth);
          if (parentVal != null) {
            return parentVal.getRange(offset, offset + fw);
          }
        }
      }
    }
    return null;
  }

  final tw = targetWidthOf(signalName);
  if (tw > 0) {
    final snapshotResult = resolveFromSnapshot(signalName, tw);
    if (snapshotResult != null) {
      return (value: snapshotResult.toString(), width: tw);
    }
  }

  // Bail on empty or slim modules (cells exist but lack connections).
  if (cells.isEmpty) {
    if (_isConstDbg) {
      debugPrint('[CONST-DBG] $rerootedPath: BAIL cells.isEmpty');
    }
    return null;
  }
  if (cells.isNotEmpty) {
    final firstCell = cells.values.first as Map<String, dynamic>;
    if (!firstCell.containsKey('connections')) {
      if (_isConstDbg) {
        debugPrint(
          '[CONST-DBG] $rerootedPath: BAIL slim module '
          '(no connections in first cell)',
        );
      }
      return null;
    }
  }

  final ports = idx.ports;
  final netnames = idx.netnames;
  final bitToSig = idx.bitToSig;
  final bitIndexInSig = idx.bitIndexInSig;
  final driverOf = idx.driverOf;

  // DFS evaluation with memoization (cross-call via evalCache).
  // Key resolved values by "$instancePath/$signalName" so different
  // instances of the same module definition don't collide.
  final cache = <String, LogicValue>{};
  // Seed from cross-call cache.
  if (evalCache != null) {
    final prefix = '$instancePath/';
    evalCache._resolvedValues.forEach((key, value) {
      if (key.startsWith(prefix)) {
        cache[key.substring(prefix.length)] = value;
      }
    });
  }
  final resolving = <String>{};

  LogicValue resolve(String name, int fw) {
    if (cache.containsKey(name)) {
      return cache[name]!;
    }

    // Check snapshot (full re-rooted path).
    final fullPath = '$instancePath/$name';
    final snapVal = snapshotLookup(fullPath);
    if (snapVal != null) {
      final lv = parseHexToLV(snapVal, fw);
      cache[name] = lv;
      return lv;
    }

    if (resolving.contains(name)) {
      return LogicValue.filled(fw, LogicValue.x);
    }
    resolving.add(name);

    try {
      final driver = driverOf[name];

      if (_isConstDbg && name.contains('const_31')) {
        debugPrint(
          '[CONST-DBG] resolve("$name", $fw): '
          'driver=${driver != null ? driver["type"] : "NULL"}, '
          'cellExists=${cells.containsKey(name)}',
        );
      }

      if (driver == null) {
        // The signal name may be a $const cell exposed as a
        // hierarchy signal.  Look it up in cells and extract the
        // value from the output port name (a Verilog literal).
        final cell = cells[name] as Map<String, dynamic>?;
        if (cell != null && cell['type'] == r'$const') {
          final cpDirs = cell['port_directions'] as Map<String, dynamic>? ?? {};
          if (_isConstDbg && name.contains('const_31')) {
            debugPrint(
              '[CONST-DBG] resolve("$name"): \$const cell path, '
              'cpDirs=$cpDirs',
            );
          }
          for (final p in cpDirs.keys) {
            if (cpDirs[p] != 'output') {
              continue;
            }
            try {
              final lv = LogicValue.ofRadixString(p);
              cache[name] = lv;
              return lv;
            } on Object {
              if (_isConstDbg && name.contains('const_31')) {
                debugPrint(
                  '[CONST-DBG] resolve("$name"): '
                  'ofRadixString("$p") FAILED',
                );
              }
              // not parseable — fall through
            }
          }
        }

        // Transitive array-element resolution: if the signal name
        // matches the pattern `parentName_N_` (LogicArray element
        // naming), recursively resolve the parent and extract the
        // sub-range.  This handles arrays with depth > 2 where
        // only the first $slice level has an explicit cell.
        // This runs BEFORE wire-alias because registration order in
        // bitToSig can cause a smaller child to be found as alias,
        // producing 'x' for uncovered bits.
        final arrayMatch = regExpFirstMatch(_arrayElementPattern, name);
        if (arrayMatch != null) {
          final parentName = arrayMatch.group(1)!;
          final elementIndex = int.parse(arrayMatch.group(2)!);
          final parentBits = sigBits[parentName];
          if (parentBits != null && parentBits.isNotEmpty) {
            final parentWidth = parentBits.length;
            final offset = elementIndex * fw;
            if (offset + fw <= parentWidth) {
              final parentVal = resolve(parentName, parentWidth);
              final slice = parentVal.getRange(offset, offset + fw);
              cache[name] = slice;
              return slice;
            }
          }
        }

        // Wire alias: bits trace to another named signal (e.g.
        // sample0_data shares bits with sampleIn0).  Resolve the
        // canonical signal instead of returning 'x'.
        final bits = sigBits[name];
        if (bits != null && bits.isNotEmpty) {
          String? aliasName;
          for (final b in bits) {
            final traceSig = bitToSig[b];
            if (traceSig != null && traceSig != name) {
              aliasName = traceSig;
              break;
            }
          }
          if (aliasName != null) {
            final aliasBits = sigBits[aliasName];
            final aliasWidth = aliasBits?.length ?? fw;
            final aliasLV = resolve(aliasName, aliasWidth);
            // If the alias covers exactly the same bits, return as-is.
            if (aliasWidth == fw) {
              cache[name] = aliasLV;
              return aliasLV;
            }
            // Extract the relevant bit positions from the alias.
            final idxMap = bitIndexInSig[aliasName] ?? {};
            final bitVals = <LogicValue>[];
            for (final b in bits) {
              final i = idxMap[b];
              if (i != null && i < aliasLV.width) {
                bitVals.add(aliasLV.getRange(i, i + 1));
              } else {
                bitVals.add(LogicValue.x);
              }
            }
            final result = LogicValue.ofIterable(bitVals);
            cache[name] = result;
            return result;
          }
        }

        return LogicValue.filled(fw, LogicValue.x);
      }

      final ct = driver['type']?.toString() ?? '';
      final conns = driver['connections'] as Map<String, dynamic>? ?? {};
      final pDirs = driver['port_directions'] as Map<String, dynamic>? ?? {};
      final params = driver['parameters'] as Map<String, dynamic>? ?? {};

      LogicValue resolveConnectionBits(List<dynamic> bits) {
        if (bits.isEmpty) {
          return LogicValue.ofString('0');
        }
        final bitVals = <LogicValue>[];
        for (final b in bits) {
          if (b is String) {
            final s = b.toLowerCase();
            if (s == '1') {
              bitVals.add(LogicValue.one);
            } else if (s == 'x' || s == 'z') {
              bitVals.add(LogicValue.x);
            } else {
              bitVals.add(LogicValue.zero);
            }
            continue;
          }
          if (b is! int) {
            return LogicValue.filled(bits.length, LogicValue.x);
          }
          final sig = bitToSig[b];
          if (sig == null) {
            return LogicValue.filled(bits.length, LogicValue.x);
          }
          final sigWidth = sigBits[sig]?.length ?? 1;
          final sigVal = resolve(sig, sigWidth);
          final bitIndex = bitIndexInSig[sig]?[b];
          if (bitIndex == null || bitIndex >= sigVal.width) {
            bitVals.add(LogicValue.x);
          } else {
            bitVals.add(sigVal.getRange(bitIndex, bitIndex + 1));
          }
        }
        return LogicValue.ofIterable(bitVals);
      }

      // $dff: sequential — try to look up the output from the snapshot
      // (the flip-flop's Q port is tracked by WaveformService).
      if (ct == r'$dff') {
        String? cellName;
        for (final ce in cells.entries) {
          if (identical(ce.value, driver)) {
            cellName = ce.key;
            break;
          }
        }
        if (cellName != null) {
          for (final pn in pDirs.keys) {
            if (pDirs[pn] != 'output') {
              continue;
            }
            final outBits = conns[pn] as List? ?? [];
            final targetBits = sigBits[name] ?? [];
            if (targetBits.isEmpty) {
              continue;
            }
            final outBitSet = outBits.whereType<int>().toSet();
            if (!targetBits.every(outBitSet.contains)) {
              continue;
            }

            final portPath = '$instancePath/$cellName/$pn';
            final portSnap = snapshotLookup(portPath);
            if (portSnap != null) {
              final portWidth = outBits.whereType<int>().length;
              final portLV = parseHexToLV(portSnap, portWidth);
              if (portWidth == fw) {
                cache[name] = portLV;
                return portLV;
              }
              final outBitList = outBits.whereType<int>().toList();
              final bitVals = <LogicValue>[];
              for (final tb in targetBits) {
                final i = outBitList.indexOf(tb);
                if (i >= 0 && i < portLV.width) {
                  bitVals.add(portLV.getRange(i, i + 1));
                } else {
                  bitVals.add(LogicValue.x);
                }
              }
              final result = LogicValue.ofIterable(bitVals);
              cache[name] = result;
              return result;
            }
          }
        }
        return LogicValue.filled(fw, LogicValue.x);
      }

      // $const: output port name is the constant literal.
      if (ct == r'$const') {
        if (_isConstDbg && name.contains('const_31')) {
          debugPrint(
            '[CONST-DBG] resolve("$name"): driver IS \$const, '
            'pDirs=$pDirs',
          );
        }
        for (final p in pDirs.keys) {
          if (pDirs[p] != 'output') {
            continue;
          }
          try {
            final lv = LogicValue.ofRadixString(p);
            cache[name] = lv;
            return lv;
          } on Object {
            if (_isConstDbg && name.contains('const_31')) {
              debugPrint(
                '[CONST-DBG] resolve("$name"): '
                'ofRadixString("$p") as driver FAILED',
              );
            }
            /* ignore parse failure */
          }
        }
        return LogicValue.filled(fw, LogicValue.x);
      }

      // $concat: Y = {B(MSB), A(LSB)}
      if (ct == r'$concat') {
        final inputPorts = pDirs.entries
            .where((entry) => entry.value == 'input')
            .map((entry) => entry.key)
            .toList();
        if (inputPorts.contains('A') && inputPorts.contains('B')) {
          inputPorts
            ..remove('A')
            ..remove('B')
            ..insertAll(0, ['A', 'B']);
        } else {
          int rangeOffset(String port) {
            final match = regExpFirstMatch(r'^\[(\d+):(\d+)\]$', port);
            if (match == null) {
              return inputPorts.indexOf(port);
            }
            return int.parse(match.group(2)!);
          }

          inputPorts.sort(
            (first, second) =>
                rangeOffset(first).compareTo(rangeOffset(second)),
          );
        }
        final inputValues = inputPorts.map((port) {
          final bits = conns[port] as List? ?? [];
          final value = resolveConnectionBits(bits.cast<dynamic>());
          return value.getRange(0, value.width);
        });
        final result = LogicValue.ofIterable(inputValues);
        cache[name] = result;
        return result;
      }

      // $slice / $struct_field: extract bits [offset..offset+width-1] from A.
      // $struct_compose: A (field) → Y (port sub-range), same bit-copy logic.
      //
      // NOTE: ROHD's LeafCellMapper emits $slice with OFFSET set to the
      // ROHD-level bit position, but the A *connection wires* already
      // reference the sliced bits.  When OFFSET is out of range for the
      // resolved A value, the connection bits are the final answer.
      if (ct == r'$slice' ||
          ct == r'$struct_field' ||
          ct == r'$struct_compose') {
        final aB = conns['A'] as List? ?? [];
        final aVal = resolveConnectionBits(aB.cast<dynamic>());
        final offset = params['OFFSET'] as int? ?? 0;
        if (offset + fw <= aVal.width) {
          final slice = aVal.getRange(offset, offset + fw);
          cache[name] = slice;
          return slice;
        }
        // OFFSET out of range — ROHD pre-sliced the connection wires.
        if (aVal.width == fw) {
          cache[name] = aVal;
          return aVal;
        }
        if (aVal.width > fw) {
          final slice = aVal.getRange(0, fw);
          cache[name] = slice;
          return slice;
        }
        return LogicValue.filled(fw, LogicValue.x);
      }

      // $struct_unpack: A (packed) → multiple named field outputs.
      if (ct == r'$struct_unpack') {
        final aB = conns['A'] as List? ?? [];
        final aVal = resolveConnectionBits(aB.cast<dynamic>());
        final targetBits = sigBits[name] ?? [];
        final fieldCount = params['FIELD_COUNT'] as int? ?? 0;
        var outPortIdx = 0;
        for (final pn in pDirs.keys) {
          if (pDirs[pn] != 'output') {
            continue;
          }
          final outBits = (conns[pn] as List? ?? []).whereType<int>().toSet();
          if (targetBits.isNotEmpty && targetBits.every(outBits.contains)) {
            int? offset;
            int? width;
            for (var i = 0; i < fieldCount; i++) {
              if (params['FIELD_${i}_NAME'] == pn) {
                offset = params['FIELD_${i}_OFFSET'] as int?;
                width = params['FIELD_${i}_WIDTH'] as int?;
                break;
              }
            }
            offset ??= outPortIdx < fieldCount
                ? params['FIELD_${outPortIdx}_OFFSET'] as int?
                : null;
            width ??= outPortIdx < fieldCount
                ? params['FIELD_${outPortIdx}_WIDTH'] as int?
                : null;
            offset ??= 0;
            width ??= fw;
            if (offset + width <= aVal.width) {
              final slice = aVal.getRange(offset, offset + width);
              cache[name] = slice;
              return slice;
            }
            break;
          }
          outPortIdx++;
        }
        if (aVal.width == fw) {
          cache[name] = aVal;
          return aVal;
        }
        if (aVal.width > fw) {
          final slice = aVal.getRange(0, fw);
          cache[name] = slice;
          return slice;
        }
        return LogicValue.filled(fw, LogicValue.x);
      }

      // $struct_pack: multiple named field inputs → Y (packed output).
      if (ct == r'$struct_pack') {
        final fieldCount = params['FIELD_COUNT'] as int? ?? 0;
        final bits = List<LogicValue>.generate(
          fw,
          (_) => LogicValue.filled(1, LogicValue.x),
        );
        for (var i = 0; i < fieldCount; i++) {
          final fName = params['FIELD_${i}_NAME'] as String?;
          final offset = params['FIELD_${i}_OFFSET'] as int? ?? 0;
          final width = params['FIELD_${i}_WIDTH'] as int? ?? 0;
          if (fName == null) {
            continue;
          }
          for (final pn in pDirs.keys) {
            if (pDirs[pn] != 'input') {
              continue;
            }
            if (pn == fName || pn.startsWith('${fName}_')) {
              final portBits = conns[pn] as List? ?? [];
              final fVal = resolveConnectionBits(portBits.cast<dynamic>());
              for (var j = 0;
                  j < width && j < fVal.width && offset + j < fw;
                  j++) {
                bits[offset + j] = fVal.getRange(j, j + 1);
              }
              break;
            }
          }
        }
        final result = LogicValue.ofIterable(bits);
        cache[name] = result;
        return result;
      }

      // Standard gate ops.
      final op = _cellTypeToOp[ct];
      if (op == null) {
        // Sub-module cell: if the cell type is a module definition,
        // look up the output port's value via the snapshot.
        if (modules.containsKey(ct)) {
          String? cellName;
          for (final ce in cells.entries) {
            if (identical(ce.value, driver)) {
              cellName = ce.key;
              break;
            }
          }
          if (cellName != null) {
            for (final pn in pDirs.keys) {
              if (pDirs[pn] != 'output') {
                continue;
              }
              final outBits = conns[pn] as List? ?? [];
              final targetBits = sigBits[name] ?? [];
              if (targetBits.isEmpty) {
                continue;
              }
              final outBitSet = outBits.whereType<int>().toSet();
              if (!targetBits.every(outBitSet.contains)) {
                continue;
              }
              final portPath = '$instancePath/$cellName/$pn';
              final portSnap = snapshotLookup(portPath);
              var portValue = portSnap;

              // If snapshot doesn't have the port value, recursively
              // evaluate into the sub-module.
              if (portValue == null) {
                final sub = evaluateSignalOnDemand(
                  modules: modules,
                  rerootedPath: portPath,
                  snapshotLookup: snapshotLookup,
                  evalCache: evalCache,
                );
                if (sub != null) {
                  portValue = sub.value;
                }
              }

              if (portValue != null) {
                final portWidth = outBits.whereType<int>().length;
                final portLV = parseHexToLV(portValue, portWidth);
                if (portWidth == fw) {
                  cache[name] = portLV;
                  return portLV;
                }
                final outBitList = outBits.whereType<int>().toList();
                final bitVals = <LogicValue>[];
                for (final tb in targetBits) {
                  final i = outBitList.indexOf(tb);
                  if (i >= 0 && i < portLV.width) {
                    bitVals.add(portLV.getRange(i, i + 1));
                  } else {
                    bitVals.add(LogicValue.x);
                  }
                }
                final result = LogicValue.ofIterable(bitVals);
                cache[name] = result;
                return result;
              }
            }
          }
        }
        return LogicValue.filled(fw, LogicValue.x);
      }

      // Gather inputs. For $mux: order S, A, B.
      final orderedPorts = <String>[];
      if (ct == r'$mux') {
        for (final n in ['S', 'A', 'B']) {
          if (pDirs.containsKey(n)) {
            orderedPorts.add(n);
          }
        }
      }
      for (final n in pDirs.keys) {
        if (!orderedPorts.contains(n)) {
          orderedPorts.add(n);
        }
      }

      final inVals = <LogicValue>[];
      for (final pName in orderedPorts) {
        if (pDirs[pName] == 'output') {
          continue;
        }
        final bits = conns[pName] as List? ?? [];
        inVals.add(resolveConnectionBits(bits.cast<dynamic>()));
      }

      if (inVals.isEmpty) {
        return LogicValue.filled(fw, LogicValue.x);
      }

      final gate = <String, dynamic>{'op': op, 'w': fw};
      final result = evalOp(op, inVals, fw, gate);
      cache[name] = result;
      return result;
    } finally {
      resolving.remove(name);
    }
  }

  // Get target signal width from the netlist bit-array length.
  var targetWidth = 1;
  final nnData = netnames[signalName] as Map<String, dynamic>?;
  if (nnData != null) {
    targetWidth = (nnData['bits'] as List?)?.whereType<int>().length ?? 1;
  } else {
    final pData = ports[signalName] as Map<String, dynamic>?;
    if (pData != null) {
      targetWidth = (pData['bits'] as List?)?.whereType<int>().length ?? 1;
    }
  }

  final result = resolve(signalName, targetWidth);

  // Store all newly resolved values back into the cross-call cache.
  if (evalCache != null) {
    for (final e in cache.entries) {
      evalCache._resolvedValues['$instancePath/${e.key}'] = e.value;
    }
  }

  return (value: result.toString(), width: result.width);
}

// ---------------------------------------------------------------------------
// Build module index from raw JSON
// ---------------------------------------------------------------------------

/// Build [_ModuleIndex] from raw module JSON data.
_ModuleIndex _buildModuleIndex(
  Map<String, dynamic> modData,
  Map<String, dynamic> cells,
) {
  final ports = modData['ports'] as Map<String, dynamic>? ?? {};
  final netnames = modData['netnames'] as Map<String, dynamic>? ?? {};
  final bitToSig = <int, String>{};
  final sigBits = <String, List<int>>{};
  final bitIndexInSig = <String, Map<int, int>>{};

  void regBits(String name, List<dynamic> bits) {
    final intBits = <int>[];
    for (final b in bits) {
      if (b is int) {
        bitToSig.putIfAbsent(b, () => name);
        intBits.add(b);
      }
    }
    if (intBits.isNotEmpty) {
      sigBits[name] = intBits;
      final indexMap = <int, int>{};
      for (var i = 0; i < intBits.length; i++) {
        indexMap[intBits[i]] = i;
      }
      bitIndexInSig[name] = indexMap;
    }
  }

  for (final e in ports.entries) {
    regBits(e.key, (e.value as Map<String, dynamic>)['bits'] as List? ?? []);
  }
  for (final e in netnames.entries) {
    regBits(e.key, (e.value as Map<String, dynamic>)['bits'] as List? ?? []);
  }

  // Build driver map: localSignalName → cell data.
  // Detect multi-driver conflicts (multiple cells driving the same signal).
  final driverOf = <String, Map<String, dynamic>>{};
  final driverCellNames = <String, String>{}; // sig → first driver instance
  final multiDriverWarnings = <String, List<String>>{};
  bool hasSameBits(List<int> signalBits, List<int> outputBits) {
    if (signalBits.length != outputBits.length) {
      return false;
    }
    final sortedSignalBits = [...signalBits]..sort();
    final sortedOutputBits = [...outputBits]..sort();
    for (var i = 0; i < sortedSignalBits.length; i++) {
      if (sortedSignalBits[i] != sortedOutputBits[i]) {
        return false;
      }
    }
    return true;
  }

  for (final cellEntry in cells.entries) {
    final cellName = cellEntry.key;
    final cellData = cellEntry.value as Map<String, dynamic>;
    final conns = cellData['connections'] as Map<String, dynamic>? ?? {};
    final pDirs = cellData['port_directions'] as Map<String, dynamic>? ?? {};
    for (final pName in pDirs.keys) {
      if (pDirs[pName] != 'output') {
        continue;
      }
      final bits = conns[pName] as List? ?? [];
      final outputBits = bits.whereType<int>().toList();
      final outSigs = sigBits.entries
          .where((entry) => hasSameBits(entry.value, outputBits))
          .map((entry) => entry.key)
          .toSet();
      if (outSigs.isEmpty) {
        for (final bit in outputBits) {
          final sig = bitToSig[bit];
          if (sig != null) {
            outSigs.add(sig);
          }
        }
      }
      for (final sig in outSigs) {
        if (driverOf.containsKey(sig)) {
          // Multi-driver conflict detected.
          final prevInstance = driverCellNames[sig] ?? '?';
          multiDriverWarnings
              .putIfAbsent(sig, () => [prevInstance])
              .add(cellName);
        }
        driverOf[sig] = cellData;
        driverCellNames.putIfAbsent(sig, () => cellName);
      }
    }
  }

  if (multiDriverWarnings.isNotEmpty) {
    debugPrint(
      '[NetlistValidation] WARNING: ${multiDriverWarnings.length} signal(s) '
      'have multiple drivers:',
    );
    for (final entry in multiDriverWarnings.entries) {
      debugPrint(
        '  "${entry.key}" driven by ${entry.value.length} cells: '
        '${entry.value.join(", ")}',
      );
    }
  }

  return _ModuleIndex(
    bitToSig: bitToSig,
    sigBits: sigBits,
    bitIndexInSig: bitIndexInSig,
    driverOf: driverOf,
    ports: ports,
    netnames: netnames,
    cells: cells,
  );
}

/// Parse a hex value string to [LogicValue].
LogicValue parseHexToLV(String value, int width) {
  final w = width < 1 ? 1 : width;
  try {
    final lv = LogicValue.ofRadixString(value);
    if (lv.width == w) {
      return lv;
    }
    if (lv.width < w) {
      return lv.zeroExtend(w);
    }
    return lv.getRange(0, w);
  } on Object {
    /* fall through to manual parse */
  }
  final lower = value.toLowerCase();
  if (lower.replaceAll('z', '').replaceAll('x', '').isEmpty) {
    return LogicValue.filled(w, LogicValue.x);
  }
  final hex = lower.startsWith('0x') ? value.substring(2) : value;
  final bi = BigInt.tryParse(hex, radix: 16) ?? BigInt.zero;
  return LogicValue.ofBigInt(bi, w);
}

// ---------------------------------------------------------------------------
// Gate evaluation
// ---------------------------------------------------------------------------

/// Match a LogicValue to target width.
LogicValue matchWidth(LogicValue lv, int w) {
  if (lv.width == w) {
    return lv;
  }
  if (lv.width < w) {
    return lv.zeroExtend(w);
  }
  return lv.getRange(0, w);
}

/// Evaluate a gate op (package-visible for on-demand eval).
LogicValue evalOp(
  String op,
  List<LogicValue> inputs,
  int width,
  Map<String, dynamic> gate,
) {
  final xOut = LogicValue.filled(width, LogicValue.x);
  switch (op) {
    case 'and':
      if (inputs.length != 2) {
        return xOut;
      }
      return matchWidth(inputs[0], width) & matchWidth(inputs[1], width);
    case 'or':
      if (inputs.length != 2) {
        return xOut;
      }
      return matchWidth(inputs[0], width) | matchWidth(inputs[1], width);
    case 'xor':
      if (inputs.length != 2) {
        return xOut;
      }
      return matchWidth(inputs[0], width) ^ matchWidth(inputs[1], width);
    case 'not':
      if (inputs.isEmpty) {
        return xOut;
      }
      return ~matchWidth(inputs[0], width);
    case 'buf':
      if (inputs.isEmpty) {
        return xOut;
      }
      return matchWidth(inputs[0], width);
    case 'mux':
      if (inputs.length != 3) {
        return xOut;
      }
      final ctrl = inputs[0];
      final d0 = matchWidth(inputs[1], width);
      final d1 = matchWidth(inputs[2], width);
      if (!ctrl.isValid) {
        return d0 == d1 ? d0 : xOut;
      }
      return ctrl[0] == LogicValue.zero ? d0 : d1;
    case 'uor':
      if (inputs.isEmpty) {
        return xOut;
      }
      return inputs[0].or();
    case 'uand':
      if (inputs.isEmpty) {
        return xOut;
      }
      return inputs[0].and();
    case 'uxor':
      if (inputs.isEmpty) {
        return xOut;
      }
      return inputs[0].xor();
    case 'eq':
      if (inputs.length != 2) {
        return xOut;
      }
      final a = inputs[0];
      final b = matchWidth(inputs[1], a.width);
      if (!a.isValid || !b.isValid) {
        return xOut;
      }
      return a == b ? LogicValue.one : LogicValue.zero;
    case 'ne':
      if (inputs.length != 2) {
        return xOut;
      }
      final a = inputs[0];
      final b = matchWidth(inputs[1], a.width);
      if (!a.isValid || !b.isValid) {
        return xOut;
      }
      return a != b ? LogicValue.one : LogicValue.zero;
    case 'sll':
      if (inputs.length != 2) {
        return xOut;
      }
      if (!inputs[1].isValid) {
        return xOut;
      }
      return matchWidth(inputs[0], width) << inputs[1];
    case 'srl':
      if (inputs.length != 2) {
        return xOut;
      }
      if (!inputs[1].isValid) {
        return xOut;
      }
      return matchWidth(inputs[0], width) >>> inputs[1];
    case 'gte':
      if (inputs.length != 2) {
        return xOut;
      }
      final w2 =
          inputs[0].width > inputs[1].width ? inputs[0].width : inputs[1].width;
      return matchWidth(inputs[0], w2) >= matchWidth(inputs[1], w2);
    case 'lt':
      if (inputs.length != 2) {
        return xOut;
      }
      final w2 =
          inputs[0].width > inputs[1].width ? inputs[0].width : inputs[1].width;
      return matchWidth(inputs[0], w2) < matchWidth(inputs[1], w2);
    case 'add':
      if (inputs.length != 2) {
        return xOut;
      }
      return matchWidth(inputs[0], width) + matchWidth(inputs[1], width);
    case 'sub':
      if (inputs.length != 2) {
        return xOut;
      }
      return matchWidth(inputs[0], width) - matchWidth(inputs[1], width);
    case 'mul':
      if (inputs.length != 2) {
        return xOut;
      }
      return matchWidth(inputs[0], width) * matchWidth(inputs[1], width);
    case 'neg':
      if (inputs.isEmpty) {
        return xOut;
      }
      return ~matchWidth(inputs[0], width) + LogicValue.ofInt(1, width);
    case 'gt':
      if (inputs.length != 2) {
        return xOut;
      }
      final w2 =
          inputs[0].width > inputs[1].width ? inputs[0].width : inputs[1].width;
      return matchWidth(inputs[0], w2) > matchWidth(inputs[1], w2);
    case 'le':
      if (inputs.length != 2) {
        return xOut;
      }
      final w2 =
          inputs[0].width > inputs[1].width ? inputs[0].width : inputs[1].width;
      return matchWidth(inputs[0], w2) <= matchWidth(inputs[1], w2);
    case 'ssrl':
      if (inputs.length != 2) {
        return xOut;
      }
      if (!inputs[1].isValid) {
        return xOut;
      }
      return matchWidth(inputs[0], width) >> inputs[1];
    case 'lnot':
      if (inputs.isEmpty) {
        return xOut;
      }
      final v = inputs[0];
      if (!v.isValid) {
        return xOut;
      }
      return v == LogicValue.filled(v.width, LogicValue.zero)
          ? LogicValue.one
          : LogicValue.zero;
    case 'land':
      if (inputs.length != 2) {
        return xOut;
      }
      if (!inputs[0].isValid || !inputs[1].isValid) {
        return xOut;
      }
      final a0 =
          inputs[0] != LogicValue.filled(inputs[0].width, LogicValue.zero);
      final b0 =
          inputs[1] != LogicValue.filled(inputs[1].width, LogicValue.zero);
      return (a0 && b0) ? LogicValue.one : LogicValue.zero;
    case 'lor':
      if (inputs.length != 2) {
        return xOut;
      }
      if (!inputs[0].isValid || !inputs[1].isValid) {
        return xOut;
      }
      final a0 =
          inputs[0] != LogicValue.filled(inputs[0].width, LogicValue.zero);
      final b0 =
          inputs[1] != LogicValue.filled(inputs[1].width, LogicValue.zero);
      return (a0 || b0) ? LogicValue.one : LogicValue.zero;
    case 'bus':
      if (inputs.isEmpty) {
        return xOut;
      }
      final lo = gate['lo'] as int;
      final hi = gate['hi'] as int? ?? (lo + width - 1);
      final rev = gate['rev'] as bool? ?? false;
      final needed = hi + 1;
      final src =
          inputs[0].width >= needed ? inputs[0] : matchWidth(inputs[0], needed);
      final slice = src.getRange(lo, hi + 1);
      return rev ? slice.reversed : slice;
    case 'swz':
      final inputWidths = (gate['iw'] as List<dynamic>?)?.cast<int>();
      if (inputWidths == null || inputWidths.length != inputs.length) {
        return xOut;
      }
      final parts = <LogicValue>[];
      for (var i = inputs.length - 1; i >= 0; i--) {
        final iw = inputWidths[i];
        final src =
            inputs[i].width >= iw ? inputs[i] : matchWidth(inputs[i], iw);
        parts.add(src.getRange(0, iw));
      }
      return parts.length == 1
          ? parts.first
          : LogicValue.ofIterable(parts.reversed);
    default:
      return xOut;
  }
}
