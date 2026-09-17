// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// module_parameter_test.dart
// Tests for ModuleParameter, ParameterExpression, ParameterConst, and
// parameterized SV generation.
//
// 2026 June
// Author: Joel Kimmel

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

/// A simple parameterized adder module for testing.
///
/// Generated SV should have parameterized port widths using WIDTH.
class ParameterizedAdder extends Module {
  Logic get sum => output('sum');

  final ModuleParameter<int> widthParam;

  ParameterizedAdder(Logic a, Logic b, {int width = 8})
      : widthParam = ModuleParameter<int>('WIDTH', defaultValue: width),
        super(name: 'parameterized_adder') {
    addModuleParameter(widthParam);

    final widthExpr = widthParam.toExpression();

    a = addInput('a', a, width: width, widthExpression: widthExpr);
    b = addInput('b', b, width: width, widthExpression: widthExpr);
    addOutput('sum', width: width, widthExpression: widthExpr);

    sum <= a + b;
  }
}

/// A parameterized wrapper that instantiates ParameterizedAdder as a submodule.
class TopWithParameterizedAdder extends Module {
  Logic get result => output('result');

  TopWithParameterizedAdder(Logic x, Logic y, {int width = 8})
      : super(name: 'top_wrapper') {
    x = addInput('x', x, width: width);
    y = addInput('y', y, width: width);
    addOutput('result', width: width);

    result <= ParameterizedAdder(x, y, width: width).sum;
  }
}

/// Module that uses ParameterConst in expressions.
class ModuleWithParameterConst extends Module {
  Logic get out => output('out');

  final ModuleParameter<int> widthParam;

  ModuleWithParameterConst(Logic inp, {int width = 8})
      : widthParam = ModuleParameter<int>('WIDTH', defaultValue: width),
        super(name: 'param_const_module') {
    addModuleParameter(widthParam);

    final widthExpr = widthParam.toExpression();

    inp = addInput('inp', inp, width: width, widthExpression: widthExpr);
    addOutput('out', width: width, widthExpression: widthExpr);

    // Use ParameterConst to reference the parameter in SV
    out <= inp & ParameterConst(widthParam, width: width);
  }
}

/// Module with localparam.
class ModuleWithLocalParam extends Module {
  Logic get out => output('out');

  ModuleWithLocalParam(Logic inp) : super(name: 'localparam_module') {
    final addrWidth =
        ModuleParameter<int>('ADDR_WIDTH', defaultValue: 4, isLocalParam: true);
    addModuleParameter(addrWidth);

    inp = addInput('inp', inp, width: 4);
    addOutput('out', width: 4);

    out <= inp;
  }
}

/// Module with both parameter and localparam.
class ModuleWithMixedParams extends Module {
  Logic get out => output('out');

  ModuleWithMixedParams(Logic inp, {int width = 8})
      : super(name: 'mixed_params_module') {
    final widthParam = ModuleParameter<int>('WIDTH', defaultValue: width);
    final depth =
        ModuleParameter<int>('DEPTH', defaultValue: 16, isLocalParam: true);
    addModuleParameter(widthParam);
    addModuleParameter(depth);

    final widthExpr = widthParam.toExpression();
    inp = addInput('inp', inp, width: width, widthExpression: widthExpr);
    addOutput('out', width: width, widthExpression: widthExpr);

    out <= inp;
  }
}

/// Module with parameterized LogicArray dimensions.
class ModuleWithParameterizedArray extends Module {
  LogicArray get out => output('out') as LogicArray;

  final ModuleParameter<int> nParam;
  final ModuleParameter<int> wParam;

  ModuleWithParameterizedArray(LogicArray inp, {int n = 4, int w = 8})
      : nParam = ModuleParameter<int>('N', defaultValue: n),
        wParam = ModuleParameter<int>('W', defaultValue: w),
        super(name: 'param_array_module') {
    addModuleParameter(nParam);
    addModuleParameter(wParam);

    final nExpr = nParam.toExpression();
    final wExpr = wParam.toExpression();

    inp = addInputArray('inp', inp,
        dimensions: [n],
        elementWidth: w,
        dimensionExpressions: [nExpr],
        elementWidthExpression: wExpr);
    addOutputArray('out',
        dimensions: [n],
        elementWidth: w,
        dimensionExpressions: [nExpr],
        elementWidthExpression: wExpr);

    out <= inp;
  }
}

/// Wrapper that instantiates ModuleWithMixedParams as a sub-module.
class WrapperOfMixedParams extends Module {
  Logic get result => output('result');

  WrapperOfMixedParams(Logic x, {int width = 8})
      : super(name: 'wrapper_mixed') {
    x = addInput('x', x, width: width);
    addOutput('result', width: width);

    result <= ModuleWithMixedParams(x, width: width).out;
  }
}

void main() {
  group('ModuleParameter', () {
    test('creates with correct name and value', () {
      final param = ModuleParameter<int>('WIDTH', defaultValue: 8);
      expect(param.name, 'WIDTH');
      expect(param.defaultValue, 8);
      expect(param.svType, 'int');
      expect(param.isLocalParam, false);
    });

    test('creates localparam', () {
      final param =
          ModuleParameter<int>('DEPTH', defaultValue: 256, isLocalParam: true);
      expect(param.isLocalParam, true);
      expect(param.name, 'DEPTH');
    });

    test('infers svType for int', () {
      final param = ModuleParameter<int>('W', defaultValue: 8);
      expect(param.svType, 'int');
    });

    test('infers svType for bool', () {
      final param = ModuleParameter<bool>('EN', defaultValue: true);
      expect(param.svType, 'bit');
    });

    test('uses explicit svType when provided', () {
      final param =
          ModuleParameter<int>('W', defaultValue: 8, svType: 'logic [3:0]');
      expect(param.svType, 'logic [3:0]');
    });

    test('generates correct SV default value for int', () {
      final param = ModuleParameter<int>('W', defaultValue: 42);
      expect(param.svDefault, '42');
    });

    test('generates correct SV default value for bool', () {
      final paramT = ModuleParameter<bool>('EN', defaultValue: true);
      expect(paramT.svDefault, "1'b1");
      final paramF = ModuleParameter<bool>('EN', defaultValue: false);
      expect(paramF.svDefault, "1'b0");
    });

    test('toSvParameterDefinition produces correct output', () {
      final param = ModuleParameter<int>('WIDTH', defaultValue: 8);
      final def = param.toSvParameterDefinition();
      expect(def.name, 'WIDTH');
      expect(def.type, 'int');
      expect(def.defaultValue, '8');
    });

    test('toExpression creates ParameterExpression for int', () {
      final param = ModuleParameter<int>('W', defaultValue: 16);
      final expr = param.toExpression();
      expect(expr.value, 16);
      expect(expr.svExpression, 'W');
    });

    test('toExpression throws for non-int', () {
      final param = ModuleParameter<bool>('EN', defaultValue: true);
      expect(param.toExpression, throwsStateError);
    });
  });

  group('ParameterExpression', () {
    test('ofParam creates from ModuleParameter', () {
      final param = ModuleParameter<int>('WIDTH', defaultValue: 8);
      final expr = ParameterExpression.ofParam(param);
      expect(expr.value, 8);
      expect(expr.svExpression, 'WIDTH');
    });

    test('ofInt creates from plain int', () {
      final expr = ParameterExpression.ofInt(42);
      expect(expr.value, 42);
      expect(expr.svExpression, '42');
    });

    test('addition with int', () {
      final expr = ParameterExpression.ofParam(
          ModuleParameter<int>('W', defaultValue: 8));
      final result = expr + 1;
      expect(result.value, 9);
      expect(result.svExpression, 'W + 1');
    });

    test('subtraction with int', () {
      final expr = ParameterExpression.ofParam(
          ModuleParameter<int>('W', defaultValue: 8));
      final result = expr - 1;
      expect(result.value, 7);
      expect(result.svExpression, 'W - 1');
    });

    test('multiplication with int', () {
      final expr = ParameterExpression.ofParam(
          ModuleParameter<int>('W', defaultValue: 4));
      final result = expr * 2;
      expect(result.value, 8);
      expect(result.svExpression, '(W) * 2');
    });

    test('integer division with int', () {
      final expr = ParameterExpression.ofParam(
          ModuleParameter<int>('W', defaultValue: 16));
      final result = expr ~/ 2;
      expect(result.value, 8);
      expect(result.svExpression, '(W) / 2');
    });

    test('left shift with int', () {
      final expr = ParameterExpression.ofParam(
          ModuleParameter<int>('W', defaultValue: 1));
      final result = expr << 3;
      expect(result.value, 8);
      expect(result.svExpression, '(W) << 3');
    });

    test('right shift with int', () {
      final expr = ParameterExpression.ofParam(
          ModuleParameter<int>('W', defaultValue: 16));
      final result = expr >> 2;
      expect(result.value, 4);
      expect(result.svExpression, '(W) >> 2');
    });

    test('chained operations', () {
      final expr = ParameterExpression.ofParam(
          ModuleParameter<int>('W', defaultValue: 8));
      final result = expr * 2 + 1;
      expect(result.value, 17);
      expect(result.svExpression, '(W) * 2 + 1');
    });

    test('addition with another ParameterExpression', () {
      final a = ParameterExpression.ofParam(
          ModuleParameter<int>('A', defaultValue: 3));
      final b = ParameterExpression.ofParam(
          ModuleParameter<int>('B', defaultValue: 5));
      final result = a + b;
      expect(result.value, 8);
      expect(result.svExpression, 'A + B');
    });
  });

  group('ParameterConst', () {
    test('holds correct value', () {
      final param = ModuleParameter<int>('WIDTH', defaultValue: 8);
      final pc = ParameterConst(param, width: 32);
      expect(pc.value, LogicValue.ofInt(8, 32));
      expect(pc.svExpression, 'WIDTH');
    });

    test('uses custom svExpression', () {
      final param = ModuleParameter<int>('WIDTH', defaultValue: 8);
      final pc = ParameterConst(param, width: 32, svExpression: 'WIDTH - 1');
      expect(pc.svExpression, 'WIDTH - 1');
    });

    test('fromExpression constructor', () {
      final param = ModuleParameter<int>('W', defaultValue: 8);
      final expr = param.toExpression() - 1;
      final pc =
          ParameterConst.fromExpression(expr, parameter: param, width: 32);
      expect(pc.value, LogicValue.ofInt(7, 32));
      expect(pc.svExpression, 'W - 1');
    });
  });

  group('Parameterized SV generation', () {
    test('module with parameters emits parameter declarations', () async {
      final mod = ParameterizedAdder(Logic(width: 8), Logic(width: 8));
      await mod.build();
      final sv = mod.generateSynth();

      // Should contain parameter declaration
      expect(sv, contains('parameter int WIDTH = 8'));
    });

    test('parameterized ports use expression-based widths', () async {
      final mod = ParameterizedAdder(Logic(width: 8), Logic(width: 8));
      await mod.build();
      final sv = mod.generateSynth();

      // Ports should use WIDTH-based ranges instead of [7:0]
      expect(sv, contains('WIDTH - 1:0'));
    });

    test('submodule instantiation includes parameter values', () async {
      final mod = TopWithParameterizedAdder(Logic(width: 8), Logic(width: 8));
      await mod.build();
      final sv = mod.generateSynth();

      // The instantiation of ParameterizedAdder should include #(.WIDTH(8))
      expect(sv, contains('.WIDTH('));
    });

    test('two instances with same params share definition', () async {
      final mod = TopWithParameterizedAdder(Logic(width: 8), Logic(width: 8));
      await mod.build();
      final sv = mod.generateSynth();

      // Should have exactly one 'module ParameterizedAdder' definition
      final moduleDefCount = 'module ParameterizedAdder'.allMatches(sv).length;
      expect(moduleDefCount, 1);
    });

    test('ParameterConst emits parameter name in SV', () async {
      final mod = ModuleWithParameterConst(Logic(width: 8));
      await mod.build();
      final sv = mod.generateSynth();

      // Should reference WIDTH in expressions instead of literal 8
      expect(sv, contains('WIDTH'));
      expect(sv, contains('parameter int WIDTH = 8'));
    });

    test('localparam module generates localparam in definition', () async {
      final mod = ModuleWithLocalParam(Logic(width: 4));
      await mod.build();
      final sv = mod.generateSynth();

      expect(sv, contains('localparam int ADDR_WIDTH = 4'));
      // Should NOT contain 'parameter int ADDR_WIDTH'
      expect(sv, isNot(contains('parameter int ADDR_WIDTH')));
    });

    test('mixed params: definition has both parameter and localparam',
        () async {
      final mod = ModuleWithMixedParams(Logic(width: 8));
      await mod.build();
      final sv = mod.generateSynth();

      expect(sv, contains('parameter int WIDTH = 8'));
      expect(sv, contains('localparam int DEPTH = 16'));
    });

    test('mixed params: instantiation only passes non-localparams', () async {
      final mod = WrapperOfMixedParams(Logic(width: 8));
      await mod.build();
      final sv = mod.generateSynth();

      // Instantiation should include WIDTH but not DEPTH
      expect(sv, contains('#(.WIDTH(8))'));
      // The instantiation line should not reference DEPTH
      expect(sv, isNot(contains('#(.WIDTH(8), .DEPTH')));
      expect(sv, isNot(contains('.DEPTH(')));
    });

    test('module registers parameters correctly', () {
      final mod = ParameterizedAdder(Logic(width: 8), Logic(width: 8));
      expect(mod.moduleParameters.length, 1);
      expect(mod.moduleParameters.first.name, 'WIDTH');
      expect(mod.moduleParameters.first.defaultValue, 8);
    });

    test('parameterized LogicArray dimensions in SV', () async {
      final mod = ModuleWithParameterizedArray(LogicArray([4], 8));
      await mod.build();
      final sv = mod.generateSynth();

      // Should have parameterized dimension and element width
      expect(sv, contains('parameter int N = 4'));
      expect(sv, contains('parameter int W = 8'));
      expect(sv, contains('[N - 1:0]'));
      expect(sv, contains('[W - 1:0]'));
    });
  });
}
