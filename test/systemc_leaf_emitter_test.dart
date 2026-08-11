// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// systemc_leaf_emitter_test.dart
// Tests for SystemC semantic leaf expression emission.
//
// 2026 July
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/systemc/systemc_leaf_emitter.dart';
import 'package:test/test.dart';

class _UnknownInlineLeaf extends Module with InlineSystemVerilog {
  _UnknownInlineLeaf(Logic dataIn) {
    dataIn = addInput('dataIn', dataIn, width: dataIn.width);
    final out = addOutput('out', width: dataIn.width);
    out <= dataIn;
  }

  @override
  String inlineVerilog(Map<String, String> inputs) =>
      'not_systemc(${inputs['dataIn']})';
}

void main() {
  final emitter = SystemCLeafEmitter(
    typeForWidth: (width) =>
        width <= 64 ? 'sc_uint<$width>' : 'sc_biguint<$width>',
  );

  group('SystemCLeafEmitter', () {
    test('renders inferred semantic operations', () {
      final andGate =
          And2Gate(Logic(name: 'a', width: 4), Logic(name: 'b', width: 4));
      final mux = Mux(
        Logic(name: 'sel'),
        Logic(name: 'a', width: 4),
        Logic(name: 'b', width: 4),
      );
      final subset = BusSubset(Logic(name: 'data', width: 8), 2, 5);

      expect(emitter.expressionFor(andGate, {'a': 'a_expr', 'b': 'b_expr'}),
          equals('a_expr & b_expr'));
      expect(
        emitter.expressionFor(mux, {
          'sel': 'sel_expr',
          'd0': 'a_expr',
          'd1': 'b_expr',
        }),
        equals('sel_expr ? sc_uint<4>(b_expr) : sc_uint<4>(a_expr)'),
      );
      expect(
        emitter.expressionFor(subset, {'original_data': 'data_expr'}),
        equals('sc_uint<4>(data_expr.range(5, 2))'),
      );
    });

    test('rejects an inline SystemVerilog-only leaf', () {
      final module = _UnknownInlineLeaf(Logic(name: 'dataIn', width: 4));

      expect(
        () => emitter.expressionFor(module, {'dataIn': 'input_expr'}),
        throwsA(isA<SynthException>()),
      );
    });
  });
}
