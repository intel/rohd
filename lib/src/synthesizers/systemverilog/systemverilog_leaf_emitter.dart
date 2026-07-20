// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// systemverilog_leaf_emitter.dart
// SystemVerilog renderer for semantic leaf expression plans.
//
// 2026 July
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';

/// Emits planned inline SystemVerilog expressions for semantic leaf gates.
class SystemVerilogLeafEmitter implements InlineLeafEmitter {
  /// Creates a leaf emitter.
  const SystemVerilogLeafEmitter();

  @override
  String expressionFor(InlineSystemVerilog module, Map<String, String> inputs) {
    final plan = LeafExpressionPlan.fromInlineModule(module, inputs);

    final op = plan.operation;
    final vals = plan.inputValues;

    if (op == LeafOperationKind.not && vals.length == 1) {
      final outputWidth = plan.meta<int>('outputWidth') ??
          plan.sourceModule.outputs.values.first.width;
      return outputWidth == 1 ? '!${vals[0]}' : '~${vals[0]}';
    }

    const binaryOps = <LeafOperationKind, String>{
      LeafOperationKind.and: '&',
      LeafOperationKind.or: '|',
      LeafOperationKind.xor: '^',
      LeafOperationKind.subtract: '-',
      LeafOperationKind.multiply: '*',
      LeafOperationKind.divide: '/',
      LeafOperationKind.modulo: '%',
      LeafOperationKind.equals: '==',
      LeafOperationKind.notEquals: '!=',
      LeafOperationKind.lessThan: '<',
      LeafOperationKind.greaterThan: '>',
      LeafOperationKind.lessThanOrEqual: '<=',
      LeafOperationKind.greaterThanOrEqual: '>=',
      LeafOperationKind.shiftLeft: '<<',
      LeafOperationKind.shiftRight: '>>',
      LeafOperationKind.arithmeticShiftRight: '>>>',
    };
    final binaryOp = binaryOps[op];
    if (binaryOp != null && vals.length >= 2) {
      return '${vals[0]} $binaryOp ${vals[1]}';
    }

    if (op == LeafOperationKind.andUnary && vals.length == 1) {
      return '&${vals[0]}';
    }
    if (op == LeafOperationKind.orUnary && vals.length == 1) {
      return '|${vals[0]}';
    }
    if (op == LeafOperationKind.xorUnary && vals.length == 1) {
      return '^${vals[0]}';
    }

    if (op == LeafOperationKind.mux && vals.length >= 3) {
      return '${vals[0]} ? ${vals[2]} : ${vals[1]}';
    }

    if (op == LeafOperationKind.power && vals.length >= 2) {
      final expr = '${vals[0]} ** ${vals[1]}';
      final selfDetermined = plan.meta<bool>('makeSelfDetermined') ?? true;
      return selfDetermined ? '{$expr}' : expr;
    }

    if (op == LeafOperationKind.busSubset && vals.length == 1) {
      final inputWidth = plan.meta<int>('inputWidth') ??
          plan.sourceModule.inputs.values.first.width;
      final startIndex = plan.meta<int>('startIndex');
      final endIndex = plan.meta<int>('endIndex');
      if (startIndex == null || endIndex == null) {
        return plan.legacySystemVerilogExpression();
      }

      final a = vals[0];
      if (inputWidth == 1) {
        return a;
      }
      if (startIndex > endIndex) {
        final swizzleContents = List.generate(
          startIndex - endIndex + 1,
          (i) => '$a[${endIndex + i}]',
        ).join(',');
        return '{$swizzleContents}';
      }

      final sliceString =
          startIndex == endIndex ? '[$startIndex]' : '[$endIndex:$startIndex]';
      return '$a$sliceString';
    }

    if (op == LeafOperationKind.replication && vals.length == 1) {
      final count = plan.meta<int>('replicationCount') ??
          ((plan.meta<int>('outputWidth') ?? 0) ~/
              (plan.meta<int>('inputWidth') ?? 1));
      return '{$count{${vals[0]}}}';
    }

    if (op == LeafOperationKind.bitIndex && vals.length >= 2) {
      final originalWidth = plan.meta<int>('originalWidth') ??
          plan.sourceModule.inputs.values.first.width;
      if (originalWidth == 1) {
        return vals[0];
      }
      return '${vals[0]}[${vals[1]}]';
    }

    if (op == LeafOperationKind.swizzle && vals.isNotEmpty) {
      final inputWidths = plan.meta<List<int>>('inputWidths');
      final inputCount = plan.meta<int>('inputCount');
      if (inputWidths == null || inputCount == null) {
        return plan.legacySystemVerilogExpression();
      }

      if (vals.length != inputCount && vals.length != inputCount + 1) {
        return plan.legacySystemVerilogExpression();
      }

      final filtered = <({String expression, int width})>[];
      for (var i = 0; i < inputWidths.length && i < vals.length; i++) {
        final width = inputWidths[i];
        if (width > 0) {
          filtered.add((expression: vals[i], width: width));
        }
      }

      if (filtered.isEmpty) {
        return plan.legacySystemVerilogExpression();
      }
      if (filtered.length == 1) {
        return filtered.single.expression;
      }

      final outWidth = filtered.fold<int>(0, (sum, entry) => sum + entry.width);
      final widthDescriptions = <({int upper, int? lower})>[];
      var upperIndex = outWidth - 1;
      for (final entry in filtered) {
        if (entry.width > 1) {
          final lowerIndex = upperIndex - entry.width + 1;
          widthDescriptions.add((upper: upperIndex, lower: lowerIndex));
        } else {
          widthDescriptions.add((upper: upperIndex, lower: null));
        }
        upperIndex -= entry.width;
      }

      var maxUpperWidth = 0;
      var maxLowerWidth = 0;
      for (final desc in widthDescriptions) {
        final upperLen = desc.upper.toString().length;
        if (upperLen > maxUpperWidth) {
          maxUpperWidth = upperLen;
        }
        if (desc.lower != null) {
          final lowerLen = desc.lower!.toString().length;
          if (lowerLen > maxLowerWidth) {
            maxLowerWidth = lowerLen;
          }
        }
      }

      final inputLines = <String>[];
      var lineUpper = outWidth - 1;
      for (var i = 0; i < filtered.length; i++) {
        final entry = filtered[i];
        final desc = widthDescriptions[i];

        final alignedDesc = desc.lower != null
            ? '${desc.upper.toString().padLeft(maxUpperWidth)}:'
                '${desc.lower!.toString().padLeft(maxLowerWidth)}'
            : desc.upper.toString().padLeft(
                  maxUpperWidth + (maxLowerWidth > 0 ? 1 + maxLowerWidth : 0),
                );

        lineUpper -= entry.width;
        final maybeComma = lineUpper >= 0 ? ',' : ' ';
        inputLines.add('${entry.expression}$maybeComma /* $alignedDesc */');
      }

      return '{\n${inputLines.join('\n')}\n}';
    }

    // Fallback keeps behavior stable while migration is incremental.
    return plan.legacySystemVerilogExpression();
  }
}
