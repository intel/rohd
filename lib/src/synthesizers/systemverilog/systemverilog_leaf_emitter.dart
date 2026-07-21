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

/// Emits inline SystemVerilog expressions for semantic leaf gates.
class SystemVerilogLeafEmitter implements InlineLeafEmitter {
  static final RegExp _singleBitSelectRegex =
      RegExp(r'^\(?([A-Za-z_][A-Za-z0-9_$]*(?:\[\d+\])*)\[(\d+)\]\)?$');
  static final RegExp _sliceSelectRegex =
      RegExp(r'^\(?([A-Za-z_][A-Za-z0-9_$]*)\[(\d+):(\d+)\]\)?$');

  /// Creates a leaf emitter.
  const SystemVerilogLeafEmitter();

  static ({String? target, int? index}) _singleBitSelect(String expression) {
    final match = _singleBitSelectRegex.firstMatch(expression.trim());
    if (match == null) {
      return (target: null, index: null);
    }

    return (target: match.group(1), index: int.parse(match.group(2)!));
  }

  static String _bitSelect(String expression, int index) {
    final match = _sliceSelectRegex.firstMatch(expression.trim());
    if (match == null) {
      return '$expression[$index]';
    }

    final target = match.group(1)!;
    final upper = int.parse(match.group(2)!);
    final lower = int.parse(match.group(3)!);
    final selectedIndex = upper >= lower ? lower + index : lower - index;
    return '$target[$selectedIndex]';
  }

  static List<({String expression, int width})> _collapseBitSelects(
    List<({bool canCollapse, String expression, int width})> operands,
  ) {
    final collapsed = <({String expression, int width})>[];

    var index = 0;
    while (index < operands.length) {
      final first = operands[index];
      final firstSel = first.width == 1 && first.canCollapse
          ? _singleBitSelect(first.expression)
          : (target: null, index: null);

      if (firstSel.target == null || firstSel.index == null) {
        collapsed.add((expression: first.expression, width: first.width));
        index++;
        continue;
      }

      var lastIndex = index;
      var expectedBit = firstSel.index! - 1;
      while (lastIndex + 1 < operands.length) {
        final next = operands[lastIndex + 1];
        final nextSelect = next.width == 1 && next.canCollapse
            ? _singleBitSelect(next.expression)
            : (target: null, index: null);
        if (nextSelect.target != firstSel.target ||
            nextSelect.index != expectedBit) {
          break;
        }
        lastIndex++;
        expectedBit--;
      }

      if (lastIndex == index) {
        collapsed.add((
          expression: '${firstSel.target}[${firstSel.index}]',
          width: 1,
        ));
      } else {
        final lowerSelect = _singleBitSelect(operands[lastIndex].expression);
        collapsed.add((
          expression:
              '${firstSel.target}[${firstSel.index}:${lowerSelect.index}]',
          width: lastIndex - index + 1,
        ));
      }

      index = lastIndex + 1;
    }

    return collapsed;
  }

  @override
  String expressionFor(InlineLeaf module, Map<String, String> inputs) {
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
    };
    final binaryOp = binaryOps[op];
    if (binaryOp != null && vals.length >= 2) {
      return '${vals[0]} $binaryOp ${vals[1]}';
    }

    if (op == LeafOperationKind.arithmeticShiftRight && vals.length >= 2) {
      return '{\$signed(${vals[0]}) >>> ${vals[1]}}';
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
        throw SynthException(
          'SystemVerilog bus subset leaf requires startIndex and endIndex '
          'metadata.',
        );
      }

      final a = vals[0];
      if (inputWidth == 1) {
        return a;
      }
      if (startIndex > endIndex) {
        final swizzleContents = List.generate(
          startIndex - endIndex + 1,
          (i) => _bitSelect(a, endIndex + i),
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
      final inputIsArrayMember =
          plan.meta<List<bool>>('inputIsArrayMember') ?? const <bool>[];
      final inputHasUnpackedArraySource =
          plan.meta<List<bool>>('inputHasUnpackedArraySource') ??
              const <bool>[];
      if (inputWidths == null || inputCount == null) {
        throw SynthException(
          'SystemVerilog swizzle leaf requires inputWidths and inputCount '
          'metadata.',
        );
      }

      if (vals.length != inputCount && vals.length != inputCount + 1) {
        throw SynthException(
          'SystemVerilog swizzle leaf expected $inputCount inputs, but saw '
          '${vals.length}.',
        );
      }

      final filtered = <({bool canCollapse, String expression, int width})>[];
      final inputExpressions = vals.take(inputCount).toList();
      for (var i = inputWidths.length - 1; i >= 0; i--) {
        if (i >= inputExpressions.length) {
          continue;
        }
        final width = inputWidths[i];
        if (width > 0) {
          final isArrayMember =
              i < inputIsArrayMember.length && inputIsArrayMember[i];
          final hasUnpackedArraySource =
              i < inputHasUnpackedArraySource.length &&
                  inputHasUnpackedArraySource[i];
          filtered.add((
            canCollapse: !isArrayMember && !hasUnpackedArraySource,
            expression: inputExpressions[i],
            width: width,
          ));
        }
      }

      if (filtered.isEmpty) {
        throw SynthException(
          'SystemVerilog swizzle leaf requires at least one non-zero-width '
          'input.',
        );
      }

      final operands = _collapseBitSelects(filtered);
      if (operands.length == 1) {
        return operands.single.expression;
      }

      final outWidth = operands.fold<int>(0, (sum, entry) => sum + entry.width);
      final widthDescriptions = <({int upper, int? lower})>[];
      var upperIndex = outWidth - 1;
      for (final entry in operands) {
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
      for (var i = 0; i < operands.length; i++) {
        final entry = operands[i];
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

    throw SynthException(
      'SystemVerilog cannot emit semantic leaf operation for '
      '${module.runtimeType}. Provide LeafCellProvider metadata or a '
      'backend-specific leaf emitter extension.',
    );
  }
}
