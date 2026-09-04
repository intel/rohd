// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// netlist_const_extractor.dart
// Extracts constant signal values from a Yosys-format netlist JSON.
//
// 2026 March
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart';

/// Extracts constant signal values from a Yosys-format netlist JSON.
///
/// Walks all modules recursively, finds `$const` cells, resolves which
/// signal each constant drives (via the bit→netname mapping), and returns
/// a map of `{ signalPath: { 'value': '0xFFFE', 'width': 16, 'name': ...,
/// 'computed': true } }` suitable for merging into a snapshot result.
class NetlistConstExtractor {
  NetlistConstExtractor._();

  /// Extract constant signal values from [netlistJson].
  ///
  /// [rootName] is the top-level instance name used as path prefix
  /// (e.g. `"FilterBank"`).  The netlist is walked recursively so that
  /// constants inside sub-modules get fully-qualified paths like
  /// `"FilterBank/ch0/coeffTap1"`.
  static Map<String, Map<String, dynamic>> extract(
    Map<String, dynamic> netlistJson,
    String rootName,
  ) {
    final modules = netlistJson['modules'] as Map<String, dynamic>? ?? {};
    if (modules.isEmpty) {
      return const {};
    }

    // Find the top module (marked with top=1 attribute, or first).
    String? topName;
    for (final entry in modules.entries) {
      final attrs = (entry.value as Map<String, dynamic>)['attributes']
          as Map<String, dynamic>?;
      if (attrs?['top'] == 1) {
        topName = entry.key;
        break;
      }
    }
    topName ??= modules.keys.first;

    final result = <String, Map<String, dynamic>>{};

    void walkModule(String path, Map<String, dynamic> moduleData) {
      final cells = moduleData['cells'] as Map<String, dynamic>? ?? {};
      final netnames = moduleData['netnames'] as Map<String, dynamic>? ?? {};
      final ports = moduleData['ports'] as Map<String, dynamic>? ?? {};

      // Build bit → signal-path map for this module scope.
      //
      // Register narrower signals first so that array elements (e.g.
      // `coefficients0_0_`, 16-bit) claim their bits before the wider
      // parent signal (e.g. `coefficients0`, 48-bit).  This ensures
      // that `$const` cells driving individual elements resolve to the
      // correct sub-signal path rather than the parent.
      final bitToSignal = <int, String>{};

      void registerBits(String sigPath, List<dynamic> bits) {
        for (final bit in bits) {
          if (bit is int) {
            bitToSignal.putIfAbsent(bit, () => sigPath);
          }
        }
      }

      for (final entry in ports.entries) {
        final pData = entry.value as Map<String, dynamic>;
        final bits = pData['bits'] as List? ?? [];
        registerBits('$path/${entry.key}', bits);
      }

      // Sort netnames by width (ascending) so narrower sub-signals
      // register their bits before wider parent signals.
      final sortedNetnames = netnames.entries.toList()
        ..sort((a, b) {
          final aBits = (a.value as Map<String, dynamic>)['bits'] as List?;
          final bBits = (b.value as Map<String, dynamic>)['bits'] as List?;
          return (aBits?.length ?? 0).compareTo(bBits?.length ?? 0);
        });

      // Also collect width info for parent-composition pass below.
      final netnameWidths = <String, int>{};
      final netnameBits = <String, List<int>>{};

      for (final entry in sortedNetnames) {
        final nData = entry.value as Map<String, dynamic>;
        final bits = nData['bits'] as List? ?? [];
        final intBits = bits.whereType<int>().toList();
        final sigPath = '$path/${entry.key}';
        netnameWidths[sigPath] = intBits.length;
        netnameBits[sigPath] = intBits;
        registerBits(sigPath, bits);
      }

      for (final cellEntry in cells.entries) {
        final cellName = cellEntry.key;
        final cellData = cellEntry.value as Map<String, dynamic>;
        final cellType = cellData['type']?.toString() ?? '';
        final connections =
            cellData['connections'] as Map<String, dynamic>? ?? {};
        final portDirs =
            cellData['port_directions'] as Map<String, dynamic>? ?? {};

        if (cellType == r'$const') {
          // Extract constant value from the port name (Verilog literal).
          for (final portName in portDirs.keys) {
            if (portDirs[portName] != 'output') {
              continue;
            }
            final bits = connections[portName] as List? ?? [];
            final outputSig = _resolveSignal(bits, bitToSignal);
            if (outputSig == null) {
              continue;
            }
            final width = bits.whereType<int>().length;
            final hexValue = _parseVerilogLiteralToHex(portName, width);

            result[outputSig] = {
              'value': hexValue,
              'width': width,
              'name': outputSig.split('/').last,
              'computed': true,
            };
          }
        } else if (modules.containsKey(cellType) &&
            !HierarchyOccurrence.isPrimitiveType(cellType)) {
          // Recurse into sub-module instances.
          walkModule(
            '$path/$cellName',
            modules[cellType] as Map<String, dynamic>,
          );
        }
      }

      // ── Compose parent signals from constant-driven sub-signals ──
      //
      // When a parent signal (e.g. `coefficients0`, 48-bit) is composed
      // entirely of sub-signals that are all constants, compose the
      // parent's value by concatenating the sub-signal constants in bit
      // order.  This allows the schematic hover to show the full value
      // for array/structure parents.
      for (final entry in sortedNetnames) {
        final sigPath = '$path/${entry.key}';
        final sigBits = netnameBits[sigPath];
        if (sigBits == null || sigBits.isEmpty) {
          continue;
        }
        // Skip if this signal already has a constant from a $const cell.
        if (result.containsKey(sigPath)) {
          continue;
        }
        final sigWidth = sigBits.length;
        // Only consider signals wider than any sub-signal that covers
        // some of the same bits — i.e. potential parent signals.
        // Check if all bits are covered by sub-signals that have
        // constant values.
        var allBitsCovered = true;
        var composedValue = BigInt.zero;
        for (var bitIdx = 0; bitIdx < sigBits.length; bitIdx++) {
          final bit = sigBits[bitIdx];
          final subSig = bitToSignal[bit];
          if (subSig == null || subSig == sigPath) {
            allBitsCovered = false;
            break;
          }
          final subConst = result[subSig];
          if (subConst == null) {
            allBitsCovered = false;
            break;
          }
          // Find the bit's position within the sub-signal.
          final subBits = netnameBits[subSig];
          if (subBits == null) {
            allBitsCovered = false;
            break;
          }
          final posInSub = subBits.indexOf(bit);
          if (posInSub < 0) {
            allBitsCovered = false;
            break;
          }
          // Extract the bit value from the sub-signal's hex constant.
          final subHex = subConst['value'] as String? ?? "1'h0";
          BigInt subVal;
          try {
            subVal = LogicValue.ofRadixString(subHex).toBigInt();
          } on Object {
            subVal = BigInt.zero;
          }
          final bitVal = (subVal >> posInSub) & BigInt.one;
          composedValue |= bitVal << bitIdx;
        }
        if (allBitsCovered && sigWidth > 0) {
          final lv = LogicValue.ofBigInt(composedValue, sigWidth);
          result[sigPath] = {
            'value': lv.toString(),
            'width': sigWidth,
            'name': sigPath.split('/').last,
            'computed': true,
          };
        }
      }
    }

    walkModule(rootName, modules[topName] as Map<String, dynamic>);
    return result;
  }

  /// Resolve a list of bit indices to a single signal path.
  /// Returns null if bits span multiple signals or none.
  static String? _resolveSignal(
    List<dynamic> bits,
    Map<int, String> bitToSignal,
  ) {
    String? signal;
    for (final bit in bits) {
      if (bit is int) {
        final sig = bitToSignal[bit];
        if (sig == null) {
          return null;
        }
        signal ??= sig;
        if (sig != signal) {
          return null;
        }
      }
    }
    return signal;
  }

  /// Parse a Verilog-style literal (e.g. `"16'hfffe"`) to radixString
  /// format. The input is already in a format compatible with
  /// [LogicValue.ofRadixString]; this method validates and normalises it.
  /// Falls back to `"1'h0"` if unparseable.
  static String _parseVerilogLiteralToHex(String literal, int fallbackWidth) {
    try {
      return LogicValue.ofRadixString(literal).toString();
    } on Object {
      return LogicValue.ofBigInt(
        BigInt.zero,
        fallbackWidth < 1 ? 1 : fallbackWidth,
      ).toString();
    }
  }
}
