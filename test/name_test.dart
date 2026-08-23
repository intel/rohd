// Copyright (C) 2023-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// name_test.dart
// Tests for definition names (including reserving them) of Modules.
//
// 2022 March 7
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class TopModule extends Module {
  TopModule(
    Logic a, {
    required bool causeDefConflict,
    required bool causeInstConflict,
  }) : super(name: 'topModule') {
    a = addInput('a', a);

    // note: order matters
    SpeciallyNamedModule(
      [a, a].swizzle(),
      reserveDefName: causeDefConflict,
      reserveInstanceName: causeInstConflict,
    );
    SpeciallyNamedModule(
      a,
      reserveDefName: true,
      reserveInstanceName: causeInstConflict,
    );
  }
}

class SpeciallyNamedModule extends Module {
  SpeciallyNamedModule(
    Logic a, {
    required bool reserveDefName,
    required bool reserveInstanceName,
    super.name = 'specialInstanceName',
    super.definitionName = 'specialName',
  }) : super(
          reserveName: reserveInstanceName,
          reserveDefinitionName: reserveDefName,
        ) {
    addInput('a', a, width: a.width);
  }
}

class RenameableModule extends Module {
  final String inputPortName;
  final String outputPortName;
  RenameableModule(
    Logic inputPort, {
    this.outputPortName = 'outputPort',
    String internalSignalName = 'internalSignal',
    String reservedInternalSignalName = 'reservedInternalSignal',
    String internalModuleInstanceName = 'internalModuleInstanceName',
    String reservedInternalModuleInstanceName =
        'reservedInternalModuleInstanceName',
    String internalModuleDefinitionName = 'internalModuleDefinitionName',
    super.definitionName = 'moduleDefinitionName',
    super.name = 'moduleInstanceName',
    super.reserveDefinitionName = true,
    super.reserveName = true,
  }) : inputPortName = inputPort.name {
    inputPort = addInput(inputPort.name, inputPort);
    final outputPort = addOutput(outputPortName);

    final internalSignal = Logic(name: internalSignalName);
    final reservedInternalSignal = Logic(name: reservedInternalSignalName);

    Combinational([internalSignal < ~inputPort]);
    Combinational([outputPort < internalSignal]);

    SpeciallyNamedModule(
      ~internalSignal,
      reserveDefName: true,
      reserveInstanceName: false,
      name: internalModuleInstanceName,
      definitionName: internalModuleDefinitionName,
    );

    SpeciallyNamedModule(
      ~reservedInternalSignal,
      reserveDefName: true,
      reserveInstanceName: true,
      name: reservedInternalModuleInstanceName,
      definitionName: internalModuleDefinitionName,
    );
  }
}

enum NameType {
  inputPort,
  outputPort,
  internalSignal,
  reservedInternalSignal,
  internalModuleInstance,
  reservedInternalModuleInstance,
  internalModuleDefinition,
  topDefinitionName,
  topName
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('signal and module naming conflicts', () {
    Future<void> runTest(RenameableModule mod) async {
      await mod.build();

      final vectors = [
        Vector({mod.inputPortName: 0}, {mod.outputPortName: 1}),
        Vector({mod.inputPortName: 1}, {mod.outputPortName: 0}),
      ];

      await SimCompare.checkFunctionalVector(mod, vectors);
      final simResult = SimCompare.iverilogVector(mod, vectors,
          moduleName: mod.definitionName);
      expect(simResult, equals(true));
    }

    Future<void> runTestGen(Map<NameType, String> names) =>
        runTest(RenameableModule(
          Logic(name: names[NameType.inputPort]),
          outputPortName: names[NameType.outputPort]!,
          internalSignalName: names[NameType.internalSignal]!,
          reservedInternalSignalName: names[NameType.reservedInternalSignal]!,
          internalModuleInstanceName: names[NameType.internalModuleInstance]!,
          reservedInternalModuleInstanceName:
              names[NameType.reservedInternalModuleInstance]!,
          internalModuleDefinitionName:
              names[NameType.internalModuleDefinition]!,
          definitionName: names[NameType.topDefinitionName],
          name: names[NameType.topName]!,
        ));

    for (var i = 0; i < NameType.values.length; i++) {
      for (var j = i + 1; j < NameType.values.length; j++) {
        final nameType1 = NameType.values[i];
        final nameType2 = NameType.values[j];
        final nameTypes = [nameType1, nameType2];

        // skip ones that actually *should* cause a failure
        //
        // Note: SystemVerilog does not allow using the same identifier for a
        // signal and an instance.
        final shouldConflict = [
          {
            NameType.internalModuleDefinition,
            NameType.topDefinitionName,
          },
          {
            NameType.inputPort,
            NameType.outputPort,
            NameType.reservedInternalSignal,
            NameType.reservedInternalModuleInstance,
          },
        ];

        var expectFail = false;
        for (final conflictSet in shouldConflict) {
          if (nameTypes.where(conflictSet.contains).length == 2) {
            expectFail = true;
            break;
          }
        }

        test('${nameType1.name} == ${nameType2.name}', () async {
          try {
            final testMap = Map.fromEntries(List.generate(
                NameType.values.length,
                (k) => MapEntry(NameType.values[k], 'uniqueName$k')));
            testMap[nameType1] = 'conflictingName';
            testMap[nameType2] = testMap[nameType1]!;
            await runTestGen(testMap);
            if (expectFail) {
              fail('Expected to fail!');
            }
          } on Exception catch (_) {
            if (!expectFail) {
              fail('Expected to pass!');
            }
          }
        });
      }
    }

    test('input port name != internal signal name', () async {
      await runTest(
          RenameableModule(Logic(name: 'apple'), internalSignalName: 'apple'));
    });
    test('output port name != internal signal name', () async {
      await runTest(RenameableModule(Logic(),
          internalSignalName: 'apple', outputPortName: 'apple'));
    });
  });

  group('definition name', () {
    test('respected with no conflicts', () async {
      final mod = SpeciallyNamedModule(
        Logic(),
        reserveDefName: false,
        reserveInstanceName: false,
      );
      await mod.build();
      final sv = mod.dumpSystemVerilog().output;
      expect(sv, contains('module specialName ('));
    });
    test('uniquified with conflicts', () async {
      final mod = TopModule(
        Logic(),
        causeDefConflict: false,
        causeInstConflict: false,
      );
      await mod.build();
      final sv = mod.dumpSystemVerilog().output;
      expect(sv, contains('module specialName ('));
      expect(sv, contains('module specialName_0 ('));
    });
    test('reserved throws exception with conflicts', () async {
      final mod = TopModule(
        Logic(),
        causeDefConflict: true,
        causeInstConflict: false,
      );
      await mod.build();
      expect(() => mod.dumpSystemVerilog().output, throwsException);
    });
  });

  group('instance name', () {
    test('uniquified with conflicts', () async {
      final mod = TopModule(
        Logic(),
        causeDefConflict: false,
        causeInstConflict: false,
      );
      await mod.build();
      final sv = mod.dumpSystemVerilog().output;

      expect(sv, contains('specialInstanceName('));
      expect(sv, contains('specialInstanceName_0('));
    });
    test('reserved throws exception with conflicts', () {
      final mod = TopModule(
        Logic(),
        causeDefConflict: false,
        causeInstConflict: true,
      );
      expect(() async {
        await mod.build();
      }, throwsException);
    });
  });
}
