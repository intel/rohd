/// Copyright (C) 2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// definition_name_test.dart
/// Tests for definition names (including reserving them) of Modules.
///
/// 2022 March 7
/// Author: Max Korbel <max.korbel@intel.com>
///

// ignore_for_file: avoid_positional_boolean_parameters
import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class TopModule extends Module {
  TopModule(Logic a, bool causeDefConflict, bool causeInstConflict)
      : super(name: 'topModule') {
    a = addInput('a', a);

    // note: order matters
    SpeciallyNamedModule([a, a].swizzle(), causeDefConflict, causeInstConflict);
    SpeciallyNamedModule(a, true, causeInstConflict);
  }
}

class SpeciallyNamedModule extends Module {
  SpeciallyNamedModule(
    Logic a,
    bool reserveDefName,
    bool reserveInstanceName, {
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
    String internalModuleInstanceName = 'internalModuleInstanceName',
    String internalModuleDefinitionName = 'internalModuleDefinitionName',
    super.definitionName = 'moduleDefinitionName',
    super.name = 'moduleInstanceName',
    super.reserveDefinitionName = true,
    super.reserveName = true,
  }) : inputPortName = inputPort.name {
    inputPort = addInput(inputPort.name, inputPort);
    final outputPort = addOutput(outputPortName);

    final internalSignal = Logic(name: internalSignalName);

    Combinational([internalSignal < ~inputPort]);
    Combinational([outputPort < internalSignal]);

    SpeciallyNamedModule(
      ~internalSignal,
      true,
      false,
      name: internalModuleInstanceName,
      definitionName: internalModuleDefinitionName,
    );
  }
}

enum NameType {
  inputPort,
  outputPort,
  internalSignal,
  internalModuleInstance,
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

    Future<void> runTestGen(Map<NameType, String> names) async =>
        runTest(RenameableModule(
          Logic(name: names[NameType.inputPort]),
          outputPortName: names[NameType.outputPort]!,
          internalSignalName: names[NameType.internalSignal]!,
          internalModuleInstanceName: names[NameType.internalModuleInstance]!,
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
        final skips = [
          [NameType.internalModuleDefinition, NameType.topDefinitionName],
          [NameType.inputPort, NameType.outputPort]
        ];

        var doSkip = false;
        for (final skip in skips) {
          if (nameTypes.contains(skip[0]) && nameTypes.contains(skip[1])) {
            doSkip = true;
            break;
          }
        }
        if (doSkip) {
          continue;
        }

        test('${nameType1.name} == ${nameType2.name}', () async {
          final testMap = Map.fromEntries(List.generate(NameType.values.length,
              (k) => MapEntry(NameType.values[k], 'uniqueName$k')));
          testMap[nameType1] = 'conflictingName';
          testMap[nameType2] = testMap[nameType1]!;
          await runTestGen(testMap);
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
      final mod = SpeciallyNamedModule(Logic(), false, false);
      await mod.build();
      expect(mod.generateSynth(), contains('module specialName('));
    });
    test('uniquified with conflicts', () async {
      final mod = TopModule(Logic(), false, false);
      await mod.build();
      final sv = mod.generateSynth();
      expect(sv, contains('module specialName('));
      expect(sv, contains('module specialName_0('));
    });
    test('reserved throws exception with conflicts', () async {
      final mod = TopModule(Logic(), true, false);
      await mod.build();
      expect(mod.generateSynth, throwsException);
    });
  });

  group('instance name', () {
    test('uniquified with conflicts', () async {
      final mod = TopModule(Logic(), false, false);
      await mod.build();
      final sv = mod.generateSynth();

      expect(sv, contains('specialInstanceName('));
      expect(sv, contains('specialInstanceName_0('));
    });
    test('reserved throws exception with conflicts', () async {
      final mod = TopModule(Logic(), false, true);
      expect(() async {
        await mod.build();
      }, throwsException);
    });
  });
}
