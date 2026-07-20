// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// leaf_backend_conformance_test.dart
// Tests for backend conformance of planned leaf expression emission.
//
// 2026 July
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/systemc/systemc_leaf_emitter.dart';
import 'package:rohd/src/synthesizers/systemverilog/systemverilog_leaf_emitter.dart';
import 'package:rohd/src/synthesizers/utilities/leaf_cell_spec.dart';
import 'package:test/test.dart';

class _BackendConformanceModule extends Module {
  _BackendConformanceModule(Logic a, Logic b, Logic sel, Logic idx) {
    a = addInput('a', a, width: 4);
    b = addInput('b', b, width: 4);
    sel = addInput('sel', sel);
    idx = addInput('idx', idx, width: 2);

    final yAnd = addOutput('y_and', width: 4);
    final yMux = addOutput('y_mux', width: 4);
    final yPow = addOutput('y_pow', width: 4);
    final yIdx = addOutput('y_idx');

    yAnd <= a & b;
    yMux <= mux(sel, a, b);
    yPow <= Power(a, b).out;
    yIdx <= IndexGate(a, idx).selection;
  }
}

class _InlineUnknownNand extends Module with InlineSystemVerilog {
  late final Logic out;

  _InlineUnknownNand(Logic a, Logic b) {
    a = addInput('a', a, width: a.width);
    b = addInput('b', b, width: b.width);
    out = addOutput('out', width: a.width);

    // Functional behavior is arbitrary for this test; semantic leaf emission
    // rejects this module because it has no backend-neutral metadata.
    out <= a & b;
  }

  @override
  String inlineVerilog(Map<String, String> inputs) =>
      '~(${inputs['a']} & ${inputs['b']})';
}

class _InlineUnknownUnaryInvert extends Module with InlineSystemVerilog {
  late final Logic out;

  _InlineUnknownUnaryInvert(Logic a) {
    a = addInput('a', a, width: a.width);
    out = addOutput('out', width: a.width);
    out <= ~a;
  }

  @override
  String inlineVerilog(Map<String, String> inputs) => '~${inputs['a']}';
}

class _InlineUnknownMuxLike extends Module with InlineSystemVerilog {
  late final Logic out;

  _InlineUnknownMuxLike(Logic sel, Logic a, Logic b) {
    sel = addInput('sel', sel);
    a = addInput('a', a, width: a.width);
    b = addInput('b', b, width: b.width);
    out = addOutput('out', width: a.width);
    out <= mux(sel, a, b);
  }

  @override
  String inlineVerilog(Map<String, String> inputs) =>
      '${inputs['sel']} ? ${inputs['b']} : ${inputs['a']}';
}

class _InlineSystemCOnly extends Module
    with InlineSystemVerilog, SystemCInlineExpression {
  late final Logic out;

  _InlineSystemCOnly(Logic dataIn) {
    dataIn = addInput('dataIn', dataIn, width: dataIn.width);
    out = addOutput('out', width: dataIn.width);
    out <= dataIn;
  }

  @override
  String inlineVerilog(Map<String, String> inputs) => inputs['dataIn']!;

  @override
  String inlineSystemC(Map<String, String> inputs) =>
      'systemc_extension(${inputs['dataIn']})';
}

class _IncompleteBusSubsetLeaf extends Module
    with InlineSystemVerilog
    implements LeafCellProvider {
  _IncompleteBusSubsetLeaf(Logic dataIn) {
    dataIn = addInput('dataIn', dataIn, width: dataIn.width);
    final out = addOutput('out', width: dataIn.width);
    out <= dataIn;
  }

  @override
  LeafCellSpec get leafCellSpec =>
      const LeafCellSpec(operation: LeafOperationKind.busSubset);

  @override
  String inlineVerilog(Map<String, String> inputs) =>
      'not_systemc(${inputs['dataIn']})';
}

class _BackendFallbackModule extends Module {
  _BackendFallbackModule(Logic a, Logic b) {
    a = addInput('a', a, width: 4);
    b = addInput('b', b, width: 4);

    final y = addOutput('y', width: 4);
    y <= _InlineUnknownNand(a, b).out;
  }
}

void main() {
  group('Leaf backend conformance', () {
    test('SystemC and planned SystemVerilog preserve key leaf semantics',
        () async {
      final emitter = SystemCLeafEmitter(
        typeForWidth: (width) =>
            width <= 64 ? 'sc_uint<$width>' : 'sc_biguint<$width>',
      );

      final andGate =
          And2Gate(Logic(name: 'a', width: 4), Logic(name: 'b', width: 4));
      final andExpr = emitter.expressionFor(andGate, {
        andGate.inputs.keys.elementAt(0): 'a_expr',
        andGate.inputs.keys.elementAt(1): 'b_expr',
      });

      final mux = Mux(
        Logic(name: 'sel'),
        Logic(name: 'a', width: 4),
        Logic(name: 'b', width: 4),
      );
      final muxExpr = emitter.expressionFor(mux, {
        mux.inputs.keys.elementAt(0): 'sel_expr',
        mux.inputs.keys.elementAt(1): 'b_expr',
        mux.inputs.keys.elementAt(2): 'a_expr',
      });

      final power =
          Power(Logic(name: 'a', width: 4), Logic(name: 'b', width: 4));
      final powerExpr = emitter.expressionFor(power, {
        power.inputs.keys.elementAt(0): 'a_expr',
        power.inputs.keys.elementAt(1): 'b_expr',
      });

      final index =
          IndexGate(Logic(name: 'a', width: 4), Logic(name: 'idx', width: 2));
      final indexExpr = emitter.expressionFor(index, {
        index.inputs.keys.elementAt(0): 'a_expr',
        index.inputs.keys.elementAt(1): 'idx_expr',
      });

      expect(andExpr, equals('a_expr & b_expr'));
      expect(muxExpr, contains('sel_expr ?'));
      expect(muxExpr, contains('sc_uint<4>(a_expr)'));
      expect(muxExpr, contains('sc_uint<4>(b_expr)'));
      expect(powerExpr, contains('pow('));
      expect(indexExpr, equals('static_cast<bool>(a_expr[idx_expr])'));

      final mod = _BackendConformanceModule(
        Logic(name: 'a', width: 4),
        Logic(name: 'b', width: 4),
        Logic(name: 'sel'),
        Logic(name: 'idx', width: 2),
      );
      await mod.build();

      final planned = mod.generateSynth();

      expect(planned, contains('assign y_and = a & b;'));
      expect(planned, contains('assign y_mux = sel ? a : b;'));
      expect(planned, contains('assign y_pow = {a ** b};'));
      expect(planned, contains('assign y_idx = a[idx];'));
    });

    test('backends reject unknown SystemVerilog-only inline module', () async {
      final systemCEmitter = SystemCLeafEmitter(
        typeForWidth: (width) =>
            width <= 64 ? 'sc_uint<$width>' : 'sc_biguint<$width>',
      );
      const systemVerilogEmitter = SystemVerilogLeafEmitter();

      final unknown = _InlineUnknownNand(
        Logic(name: 'a', width: 4),
        Logic(name: 'b', width: 4),
      );
      expect(
        () => systemCEmitter.expressionFor(
          unknown,
          {'a': 'a_expr', 'b': 'b_expr'},
        ),
        throwsA(isA<SynthException>()),
      );
      expect(
        () => systemVerilogEmitter.expressionFor(
          unknown,
          {'a': 'a_expr', 'b': 'b_expr'},
        ),
        throwsA(isA<SynthException>()),
      );

      final mod = _BackendFallbackModule(
        Logic(name: 'a', width: 4),
        Logic(name: 'b', width: 4),
      );
      await mod.build();

      expect(
        mod.generateSynth,
        throwsA(isA<SynthException>()),
      );
    });

    test('unknown inline module is rejected by SystemVerilog synthesis',
        () async {
      final mod = _BackendFallbackModule(
        Logic(name: 'a', width: 4),
        Logic(name: 'b', width: 4),
      );
      await mod.build();

      expect(
        mod.generateSynth,
        throwsA(isA<SynthException>()),
      );
    });

    test('SystemC rejects unknown inline module matrix', () {
      final emitter = SystemCLeafEmitter(
        typeForWidth: (width) =>
            width <= 64 ? 'sc_uint<$width>' : 'sc_biguint<$width>',
      );

      final scenarios = <({
        InlineLeaf module,
        Map<String, String> inputs,
      })>[
        (
          module: _InlineUnknownNand(
            Logic(name: 'a', width: 4),
            Logic(name: 'b', width: 4),
          ),
          inputs: {'a': 'a_expr', 'b': 'b_expr'},
        ),
        (
          module: _InlineUnknownUnaryInvert(Logic(name: 'u', width: 5)),
          inputs: {'a': 'u_expr'},
        ),
        (
          module: _InlineUnknownMuxLike(
            Logic(name: 'sel'),
            Logic(name: 'a', width: 4),
            Logic(name: 'b', width: 4),
          ),
          inputs: {'sel': 'sel_expr', 'a': 'a_expr', 'b': 'b_expr'},
        ),
      ];

      for (final scenario in scenarios) {
        expect(
          () => emitter.expressionFor(scenario.module, scenario.inputs),
          throwsA(isA<SynthException>()),
        );
      }
    });

    test('SystemC uses an explicit backend extension for unknown leaves', () {
      final emitter = SystemCLeafEmitter(
        typeForWidth: (width) =>
            width <= 64 ? 'sc_uint<$width>' : 'sc_biguint<$width>',
      );
      final module = _InlineSystemCOnly(Logic(name: 'dataIn', width: 4));

      expect(
        emitter.expressionFor(module, {'dataIn': 'input_expr'}),
        equals('systemc_extension(input_expr)'),
      );
    });

    test('SystemC rejects incomplete bus subset metadata', () {
      final emitter = SystemCLeafEmitter(
        typeForWidth: (width) =>
            width <= 64 ? 'sc_uint<$width>' : 'sc_biguint<$width>',
      );
      final module = _IncompleteBusSubsetLeaf(Logic(name: 'dataIn', width: 4));

      expect(
        () => emitter.expressionFor(module, {'dataIn': 'input_expr'}),
        throwsA(isA<SynthException>()),
      );
    });
  });
}
