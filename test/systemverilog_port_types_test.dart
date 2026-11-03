// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// systemverilog_port_types_test.dart
// Tests for SystemVerilog port object and data types.
//
// 2026 July
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class _PortStructure extends LogicStructure {
  final bool asNet;

  factory _PortStructure({String? name, bool asNet = false}) =>
      _PortStructure._(
        (asNet ? LogicNet.new : Logic.new)(width: 2, name: 'first'),
        (asNet ? LogicNet.new : Logic.new)(width: 6, name: 'second'),
        name: name,
        asNet: asNet,
      );

  _PortStructure._(Logic first, Logic second,
      {required String? name, required this.asNet})
      : super([first, second], name: name ?? 'portStructure');

  @override
  _PortStructure clone({String? name}) =>
      _PortStructure(name: name ?? this.name, asNet: asNet);
}

class _PortTypesModule extends Module {
  _PortTypesModule({bool includeUnpackedInOut = true}) {
    final scalarIn = addInput('scalarIn', Logic(width: 8), width: 8);
    addOutput('scalarOut', width: 8) <= scalarIn;
    addInOut('scalarInOut', LogicNet(width: 8), width: 8);

    final structureIn = addTypedInput('structureIn', _PortStructure());
    addTypedOutput('structureOut', structureIn.clone) <= structureIn;
    addTypedInOut('structureInOut', _PortStructure(asNet: true));

    final packedArrayIn = addTypedInput('packedArrayIn', LogicArray([2, 3], 4));
    addTypedOutput('packedArrayOut', packedArrayIn.clone) <= packedArrayIn;
    addTypedInOut('packedArrayInOut', LogicArray.net([2, 3], 4));

    final unpackedArrayIn = addTypedInput(
        'unpackedArrayIn', LogicArray([2, 3], 4, numUnpackedDimensions: 1));
    addTypedOutput('unpackedArrayOut', unpackedArrayIn.clone) <=
        unpackedArrayIn;
    if (includeUnpackedInOut) {
      addTypedInOut('unpackedArrayInOut',
          LogicArray.net([2, 3], 4, numUnpackedDimensions: 1));
    }
  }
}

class _NestedPortTypesModule extends Module {
  _NestedPortTypesModule() {
    final source =
        TypedLogicArray<TypedLogicArray<Logic, LogicValue>, LogicValue>(
      [2],
      ({name}) => TypedLogicArray<Logic, LogicValue>(
        [3],
        ({name}) => Logic(name: name, width: 3),
        name: name,
      ),
      numUnpackedDimensions: 1,
    );
    final valuesIn = addTypedInput('valuesIn', source);
    final child = _NestedPortTypesChild(valuesIn);
    addTypedOutput('valuesOut', source.clone).gets(child.valuesOut);
  }
}

class _NestedPortTypesChild extends Module {
  late final TypedLogicArray<TypedLogicArray<Logic, LogicValue>, LogicValue>
      valuesOut;

  _NestedPortTypesChild(
      TypedLogicArray<TypedLogicArray<Logic, LogicValue>, LogicValue>
          valuesIn) {
    valuesIn = addTypedInput('valuesIn', valuesIn);
    valuesOut = addTypedOutput('valuesOut', valuesIn.clone);
    for (var outer = 0; outer < 2; outer++) {
      for (var inner = 0; inner < 3; inner++) {
        valuesOut.at([outer]).at([inner]) <= valuesIn.at([outer]).at([inner]);
      }
    }
  }
}

class _ZeroWidthRoot extends Module {
  _ZeroWidthRoot() {
    final emptyInput = addInput('emptyInput', Logic(width: 0), width: 0);
    final emptyOutput = addOutput('emptyOutput', width: 0);
    addInOut('emptyInOut', LogicNet(width: 0), width: 0);
    emptyOutput <= emptyInput;
    addOutput('isEmpty') <= emptyInput.eq(Const(0, width: 0));
  }
}

class _ZeroWidthLeaf extends Module {
  _ZeroWidthLeaf(Logic emptyInput) {
    emptyInput = addInput('emptyInput', emptyInput, width: 0);
    final emptyOutput = addOutput('emptyOutput', width: 0);
    emptyOutput <= emptyInput;
    addOutput('isEmpty') <= emptyInput.eq(Const(0, width: 0));
  }
}

class _ZeroWidthNestedTop extends Module {
  _ZeroWidthNestedTop() {
    final emptyLink = Logic(width: 0, name: 'emptyLink');
    final child = _ZeroWidthLeaf(emptyLink);
    addOutput('isEmpty') <= child.output('isEmpty');
  }
}

class _ZeroWidthSequentialConditional extends Module {
  _ZeroWidthSequentialConditional() {
    final clk = addInput('clk', Logic());
    final reset = addInput('reset', Logic());
    final select = addInput('select', Logic());
    final emptyIn = addInput('emptyIn', Logic(width: 0), width: 0);
    final dataIn = addInput('dataIn', Logic(width: 8), width: 8);
    final emptyOut = addOutput('emptyOut', width: 0);
    final dataOut = addOutput('dataOut', width: 8);

    Sequential(clk, reset: reset, [
      If(
        select,
        then: [emptyOut < emptyIn, dataOut < dataIn],
        orElse: [emptyOut < emptyIn, dataOut < 0],
      ),
    ]);
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  final testCases = [
    (
      name: 'historical port types by default',
      configuration: const SystemVerilogSynthesizerConfiguration(),
      inputPrefix: 'input logic',
      outputPrefix: 'output logic',
      inOutPrefix: 'inout wire',
    ),
    (
      name: 'explicit object and data types',
      configuration: const SystemVerilogSynthesizerConfiguration(
        inputPortType: SystemVerilogPortTypeConfiguration(),
        outputPortType: SystemVerilogPortTypeConfiguration(),
        inOutPortType: SystemVerilogPortTypeConfiguration(),
      ),
      inputPrefix: 'input wire logic',
      outputPrefix: 'output var logic',
      inOutPrefix: 'inout wire logic',
    ),
    (
      name: 'implicit object and data types',
      configuration: const SystemVerilogSynthesizerConfiguration(
        inputPortType: SystemVerilogPortTypeConfiguration(
          objectType: SystemVerilogPortType.implicit,
          dataType: SystemVerilogPortType.implicit,
        ),
        outputPortType: SystemVerilogPortTypeConfiguration(
          objectType: SystemVerilogPortType.implicit,
          dataType: SystemVerilogPortType.implicit,
        ),
        inOutPortType: SystemVerilogPortTypeConfiguration(
          objectType: SystemVerilogPortType.implicit,
          dataType: SystemVerilogPortType.implicit,
        ),
      ),
      inputPrefix: 'input',
      outputPrefix: 'output',
      inOutPrefix: 'inout',
    ),
    (
      name: 'independently configured port directions',
      configuration: const SystemVerilogSynthesizerConfiguration(
        inputPortType: SystemVerilogPortTypeConfiguration(
          dataType: SystemVerilogPortType.implicit,
        ),
        outputPortType: SystemVerilogPortTypeConfiguration(
          objectType: SystemVerilogPortType.implicit,
          dataType: SystemVerilogPortType.implicit,
        ),
        inOutPortType: SystemVerilogPortTypeConfiguration(
          objectType: SystemVerilogPortType.implicit,
        ),
      ),
      inputPrefix: 'input wire',
      outputPrefix: 'output',
      inOutPrefix: 'inout logic',
    ),
  ];

  for (final testCase in testCases) {
    test(testCase.name, () async {
      final module = _PortTypesModule();
      await module.build();

      final sv =
          SystemVerilogService(module, configuration: testCase.configuration)
              .output;

      final declarations = {
        testCase.inputPrefix: [
          '[7:0] scalarIn',
          '[7:0] structureIn',
          '[1:0][2:0][3:0] packedArrayIn',
          '[2:0][3:0] unpackedArrayIn [1:0]',
        ],
        testCase.outputPrefix: [
          '[7:0] scalarOut',
          '[7:0] structureOut',
          '[1:0][2:0][3:0] packedArrayOut',
          '[2:0][3:0] unpackedArrayOut [1:0]',
        ],
        testCase.inOutPrefix: [
          '[7:0] scalarInOut',
          '[7:0] structureInOut',
          '[1:0][2:0][3:0] packedArrayInOut',
          '[2:0][3:0] unpackedArrayInOut [1:0]',
        ],
      };

      for (final MapEntry(key: prefix, value: suffixes)
          in declarations.entries) {
        for (final suffix in suffixes) {
          expect(sv, contains('$prefix $suffix'));
        }
      }

      final iverilogModule = _PortTypesModule(includeUnpackedInOut: false);
      await iverilogModule.build();
      SimCompare.checkIverilogVector(
        iverilogModule,
        [],
        buildOnly: true,
        synthesizerConfiguration: testCase.configuration,
      );
    });
  }

  test('root definition omits zero-width ports', () async {
    final module = _ZeroWidthRoot();
    await module.build();

    final sv = module.dumpSystemVerilog();

    expect(sv, contains('output logic isEmpty'), reason: sv);
    expect(sv, contains("assign isEmpty = 1'b0 == 1'b0;"), reason: sv);
    expect(sv, isNot(contains('input logic emptyInput')), reason: sv);
    expect(sv, isNot(contains('output logic emptyOutput')), reason: sv);
    expect(sv, isNot(contains('inout wire emptyInOut')), reason: sv);
    expect(sv, isNot(contains('[-1:0]')), reason: sv);

    final vectors = [
      Vector(
        {'emptyInput': LogicValue.empty},
        {'emptyOutput': LogicValue.empty, 'isEmpty': 1},
      ),
    ];
    await SimCompare.checkFunctionalVector(module, vectors);
    SimCompare.checkIverilogVector(module, vectors);
  });

  test('nested definitions omit zero-width port connections', () async {
    final module = _ZeroWidthNestedTop();
    await module.build();

    final sv = module.dumpSystemVerilog();

    expect(sv, contains('output logic isEmpty'), reason: sv);
    expect(sv, contains("assign isEmpty = 1'b0 == 1'b0;"), reason: sv);
    expect(sv, isNot(contains('input logic emptyInput')), reason: sv);
    expect(sv, isNot(contains('output logic emptyOutput')), reason: sv);
    expect(sv, isNot(contains('.emptyInput(')), reason: sv);
    expect(sv, isNot(contains('.emptyOutput(')), reason: sv);
    expect(sv, isNot(contains('logic emptyLink;')), reason: sv);
    expect(sv, isNot(contains('[-1:0]')), reason: sv);

    final vectors = [
      Vector({}, {'isEmpty': 1})
    ];
    await SimCompare.checkFunctionalVector(module, vectors);
    SimCompare.checkIverilogVector(module, vectors);
  });

  test('sequential conditionals omit zero-width assignments', () async {
    final module = _ZeroWidthSequentialConditional();
    await module.build();

    final sv = module.dumpSystemVerilog();

    expect(sv, contains('always_ff'), reason: sv);
    expect(sv, contains('<= dataIn'), reason: sv);
    expect(sv, isNot(contains('emptyIn')), reason: sv);
    expect(sv, isNot(contains('emptyOut')), reason: sv);
    expect(sv, isNot(contains('[-1:0]')), reason: sv);

    SimCompare.checkIverilogVector(module, [], buildOnly: true);
  });

  // Icarus 12.0 compiles the variable modes below, but a child-driven
  // unpacked output remains X. Verilator 5.020 simulates every mode.
  test('nested outputs honor configured object and data types', () async {
    final module = _NestedPortTypesModule();
    await module.build();
    final input = LogicValue.ofIterable([
      for (var value = 1; value <= 6; value++) LogicValue.ofInt(value, 3),
    ]);
    final vectors = [
      Vector({'valuesIn': input}, {'valuesOut': input}),
    ];
    final configurations = [
      (
        name: 'inferred object type',
        configuration: const SystemVerilogSynthesizerConfiguration(),
        declarations: {
          'output logic [8:0] valuesOut [1:0]': 1,
          'output wire logic [8:0] valuesOut [1:0]': 1,
        },
        checkIverilog: true,
      ),
      (
        name: 'explicit variable',
        configuration: const SystemVerilogSynthesizerConfiguration(
          outputPortType: SystemVerilogPortTypeConfiguration(),
        ),
        declarations: {'output var logic [8:0] valuesOut [1:0]': 2},
        checkIverilog: false,
      ),
      (
        name: 'implicit net',
        configuration: const SystemVerilogSynthesizerConfiguration(
          outputPortType: SystemVerilogPortTypeConfiguration(
            objectType: SystemVerilogPortType.implicit,
            dataType: SystemVerilogPortType.implicit,
          ),
        ),
        declarations: {'output [8:0] valuesOut [1:0]': 2},
        checkIverilog: true,
      ),
    ];

    for (final configuration in configurations) {
      final sv = module.dumpSystemVerilog(
        configuration: configuration.configuration,
      );
      for (final declaration in configuration.declarations.entries) {
        expect(
          RegExp(RegExp.escape(declaration.key)).allMatches(sv),
          hasLength(declaration.value),
          reason: configuration.name,
        );
      }
      if (configuration.checkIverilog) {
        SimCompare.checkIverilogVector(
          module,
          vectors,
          synthesizerConfiguration: configuration.configuration,
        );
      } else {
        SimCompare.checkIverilogVector(
          module,
          const [],
          buildOnly: true,
          synthesizerConfiguration: configuration.configuration,
        );
      }
      SimCompare.checkVerilatorVector(
        module,
        vectors,
        synthesizerConfiguration: configuration.configuration,
      );
    }
  }, tags: ['verilator']);
}
