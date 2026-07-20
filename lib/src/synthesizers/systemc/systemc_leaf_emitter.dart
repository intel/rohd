// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// systemc_leaf_emitter.dart
// SystemC renderer for semantic leaf expression plans.
//
// 2026 July
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/systemc/systemc_mixins.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';

/// Emits backend-specific SystemC/C++ expressions for semantic leaf gates.
class SystemCLeafEmitter implements InlineLeafEmitter {
  /// Returns the SystemC type for a requested signal width.
  final String Function(int width) typeForWidth;

  /// Creates a leaf emitter.
  const SystemCLeafEmitter({required this.typeForWidth});

  /// Emits a SystemC expression for an inline-style module [m].
  ///
  /// [inputs] maps module input port names to SystemC read expressions.
  @override
  String expressionFor(InlineSystemVerilog m, Map<String, String> inputs) {
    final plan = LeafExpressionPlan.fromInlineModule(m, inputs);
    final op = plan.operation;

    // ── Single-output bitwise gates ──
    if (op == LeafOperationKind.not || m is NotGate) {
      final outputWidth = plan.meta<int>('outputWidth') ??
          (m as Module).outputs.values.first.width;
      if (outputWidth == 1) {
        return '!${inputs.values.first}';
      }
      return '~${inputs.values.first}';
    }

    // ── Binary operators ──
    const binaryOps = <LeafOperationKind, String>{
      LeafOperationKind.and: '&',
      LeafOperationKind.or: '|',
      LeafOperationKind.xor: '^',
      LeafOperationKind.subtract: '-',
      LeafOperationKind.multiply: '*',
    };
    final binOp = binaryOps[op];
    if (binOp != null) {
      final vals = plan.inputValues;
      return '${vals[0]} $binOp ${vals[1]}';
    }
    if (op == LeafOperationKind.divide ||
        op == LeafOperationKind.modulo ||
        m is Divide ||
        m is Modulo) {
      final vals = plan.inputValues;
      final divideOp =
          (op == LeafOperationKind.divide || m is Divide) ? '/' : '%';
      return '(${vals[1]} != 0 ? ${vals[0]} $divideOp ${vals[1]} : 0)';
    }
    if (op == LeafOperationKind.power || m is Power) {
      final vals = plan.inputValues;
      final w = plan.meta<int>('inputWidth') ??
          (m as Module).inputs.values.first.width;
      return '${typeForWidth(w)}'
          '(static_cast<uint64_t>'
          '(pow(static_cast<double>(${vals[0]}),'
          ' static_cast<double>(${vals[1]}))))';
    }

    // ── Comparisons ──
    const cmpOps = <LeafOperationKind, String>{
      LeafOperationKind.equals: '==',
      LeafOperationKind.notEquals: '!=',
      LeafOperationKind.lessThan: '<',
      LeafOperationKind.greaterThan: '>',
      LeafOperationKind.lessThanOrEqual: '<=',
      LeafOperationKind.greaterThanOrEqual: '>=',
    };
    final cmpOp = cmpOps[op];
    if (cmpOp != null) {
      final vals = plan.inputValues;
      return '${vals[0]} $cmpOp ${vals[1]}';
    }

    // ── Shifts ──
    if (op == LeafOperationKind.shiftLeft ||
        op == LeafOperationKind.shiftRight ||
        op == LeafOperationKind.arithmeticShiftRight ||
        m is LShift ||
        m is RShift ||
        m is ARShift) {
      final vals = plan.inputValues;
      final w = plan.meta<int>('inputWidth') ??
          (m as Module).inputs.values.first.width;
      final outType = typeForWidth(w);
      final shiftAmtWidth = plan.meta<int>('shiftAmountWidth') ??
          (m as Module).inputs.values.toList()[1].width;
      final shiftExpr =
          shiftAmtWidth == 1 ? '(int)(${vals[1]})' : '(${vals[1]}).to_int()';
      final isArithmetic =
          op == LeafOperationKind.arithmeticShiftRight || m is ARShift;
      if (isArithmetic) {
        final signedType = w <= 64 ? 'sc_int<$w>' : 'sc_bigint<$w>';
        final shiftOp = '$outType(($signedType(${vals[0]})) >> $shiftExpr)';
        if (shiftAmtWidth > 31) {
          final overflow = '$outType(($signedType(${vals[0]})) >> ${w - 1})';
          return '(${vals[1]} >= $w) ? $overflow : $shiftOp';
        }
        return shiftOp;
      }
      final shiftOpSymbol =
          (op == LeafOperationKind.shiftLeft || m is LShift) ? '<<' : '>>';
      final shiftOp = '$outType(${vals[0]} $shiftOpSymbol $shiftExpr)';
      if (shiftAmtWidth > 31) {
        return '(${vals[1]} >= $w) ? $outType(0) : $shiftOp';
      }
      return shiftOp;
    }

    // ── Unary reductions ──
    if (op == LeafOperationKind.andUnary ||
        op == LeafOperationKind.orUnary ||
        op == LeafOperationKind.xorUnary ||
        m is AndUnary ||
        m is OrUnary ||
        m is XorUnary) {
      final inputWidth = plan.meta<int>('inputWidth') ??
          (m as Module).inputs.values.first.width;
      if (inputWidth == 1) {
        return 'static_cast<bool>(${inputs.values.first})';
      }
      if (op == LeafOperationKind.andUnary || m is AndUnary) {
        return '${inputs.values.first}.and_reduce()';
      } else if (op == LeafOperationKind.orUnary || m is OrUnary) {
        return '${inputs.values.first}.or_reduce()';
      } else {
        return '${inputs.values.first}.xor_reduce()';
      }
    }

    // ── Bus subset ──
    if (op == LeafOperationKind.busSubset || m is BusSubset) {
      final inputWidth = plan.meta<int>('inputWidth') ??
          (m as Module).inputs.values.first.width;
      final startIndex = plan.meta<int>('startIndex') ??
          (m is BusSubset ? m.startIndex : null);
      final endIndex =
          plan.meta<int>('endIndex') ?? (m is BusSubset ? m.endIndex : null);
      if (startIndex == null || endIndex == null) {
        throw SynthException(
          'SystemC bus subset leaf requires startIndex and endIndex metadata.',
        );
      }

      final a = inputs.values.first;
      if (inputWidth == 1 && startIndex == 0 && endIndex == 0) {
        return a;
      }
      if (startIndex == endIndex) {
        return 'static_cast<bool>($a[$startIndex])';
      }
      if (startIndex > endIndex) {
        final bits = List.generate(startIndex - endIndex + 1,
            (i) => 'sc_uint<1>($a[${endIndex + i}])');
        return '(${bits.join(', ')})';
      }
      final w = endIndex - startIndex + 1;
      final rangeType = w <= 64 ? 'sc_uint' : 'sc_biguint';
      return '$rangeType<$w>($a.range($endIndex, $startIndex))';
    }

    // ── Dynamic index ──
    if (op == LeafOperationKind.bitIndex || m is IndexGate) {
      final vals = plan.inputValues;
      return 'static_cast<bool>(${vals[0]}[${vals[1]}])';
    }

    // ── Mux ──
    if (op == LeafOperationKind.mux || m is Mux) {
      final vals = plan.inputValues;
      final w = plan.meta<int>('outputWidth') ?? (m as Mux).out.width;
      final utype = typeForWidth(w);
      return '${vals[0]} ? $utype(${vals[2]}) : $utype(${vals[1]})';
    }

    // ── Replication ──
    if (op == LeafOperationKind.replication || m is ReplicationOp) {
      final a = inputs.values.first;
      final inputWidth = plan.meta<int>('inputWidth') ??
          (m as Module).inputs.values.first.width;
      final outputWidth = plan.meta<int>('outputWidth') ??
          (m as ReplicationOp).replicated.width;
      final numReps = outputWidth ~/ inputWidth;
      if (inputWidth == 1) {
        final utype = typeForWidth(outputWidth);
        return '$utype($a ? $utype(-1) : $utype(0))';
      }
      final copies = List.filled(numReps, a);
      return '(${copies.join(', ')})';
    }

    // ── Swizzle ──
    if (op == LeafOperationKind.swizzle || m is Swizzle) {
      final inputWidths = plan.meta<List<int>>('inputWidths') ??
          (m as Module).inputs.values.map((input) => input.width).toList();
      final exprList = <String>[];
      var i = 0;
      for (final expr in inputs.values) {
        final w = inputWidths[i];
        if (w == 0) {
          i++;
          continue;
        }
        if (w == 1) {
          exprList.add('sc_uint<1>($expr)');
        } else {
          exprList.add(expr);
        }
        i++;
      }
      if (exprList.length == 1) {
        return exprList.first;
      }
      return '(${exprList.reversed.join(', ')})';
    }

    if (m is SystemCInlineExpression) {
      return (m as SystemCInlineExpression).inlineSystemC(inputs);
    }

    throw SynthException(
      'SystemC cannot emit semantic leaf operation for ${m.runtimeType}. '
      'Provide LeafCellProvider metadata or implement SystemCInlineExpression.',
    );
  }
}
