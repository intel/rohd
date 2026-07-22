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

      final sv = module.generateSynth(configuration: testCase.configuration);

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
}
