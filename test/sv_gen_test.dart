// Copyright (C) 2023-2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// sv_gen_test.dart
// Tests for SystemVerilog generation.
//
// 2023 October 4
// Author: Max Korbel <max.korbel@intel.com>

import 'dart:io';

import 'package:collection/collection.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class AlphabeticalModule extends Module {
  AlphabeticalModule(Logic l, Logic a, Logic w) {
    l = addInput('l', l);
    a = addInput('a', a);
    w = addInput('w', w);

    final o = Logic(name: 'o');
    final c = Logic(name: 'c');
    final y = Logic(name: 'y');

    c <= l & w;
    o <= a | l;
    y <= w ^ l;

    addOutput('m');
    addOutput('x') <= c + o + y;
    addOutput('b');
  }
}

class AlphabeticalWidthsModule extends Module {
  AlphabeticalWidthsModule() {
    final l = addInput('l', Logic(width: 4), width: 4);
    final a = addInput('a', Logic(width: 3), width: 3);
    final w = addInput('w', Logic(width: 2), width: 2);

    final o = Logic(name: 'o', width: 4);
    final c = Logic(name: 'c', width: 3);
    final y = Logic(name: 'y', width: 2);

    c <= a & a;
    o <= l | l;
    y <= w ^ w;

    addOutput('m', width: 4) <= o + o;
    addOutput('x', width: 2) <= y + y;
    addOutput('b', width: 3) <= c + c;
  }
}

class AlphabeticalSubmodulePorts extends Module {
  AlphabeticalSubmodulePorts() {
    final l = addInput('l', Logic());
    final a = addInput('a', Logic());
    final w = addInput('w', Logic());

    final am = AlphabeticalModule(l, a, w);

    addOutput('m') <= am.output('m');
    addOutput('x') <= am.output('x');
    addOutput('b') <= am.output('b');
  }
}

class TopWithExpressions extends Module {
  TopWithExpressions(Logic a, Logic b) {
    a = addInput('a', a);
    b = addInput('b', b, width: 5);

    addOutput('o') <= SubForExpressions(a | b[2]).o;
  }
}

class SubForExpressions extends Module {
  Logic get o => output('o');
  SubForExpressions(Logic a) {
    a = addInput('a', a);
    addOutput('o') <= a;
  }
}

class ModuleWithFloatingSignals extends Module {
  ModuleWithFloatingSignals() {
    final a = addInput('apple', Logic());
    addOutput('orange');

    final s = Logic(name: 'squash', naming: Naming.reserved);

    Logic(name: 'xylophone') <= a | s;
  }
}

class TopCustomSvWrap extends Module {
  TopCustomSvWrap(Logic a, Logic b,
      {bool useOld = false, bool banExpressions = false}) {
    a = addInput('a', a);
    b = addInput('b', b);

    if (useOld) {
      SubCustomSv([a, b], banExpressions: banExpressions);
    } else {
      SubSv([a, b], banExpressions: banExpressions);
    }
  }
}

class SimpleStruct extends LogicStructure {
  final Naming? elementNaming;
  SimpleStruct({super.name = 'SimpleStruct', required this.elementNaming})
      : super([
          Logic(name: 'field4', width: 4, naming: elementNaming),
          Logic(name: 'field8', width: 8, naming: elementNaming),
        ]);

  @override
  SimpleStruct clone({String? name}) =>
      SimpleStruct(name: name ?? this.name, elementNaming: elementNaming);
}

//TODO: test removal of bussubsets and swizzles as well

class TopWithUnusedSubModPorts extends Module {
  //TODO:
  // types of ports to not use:
  // - inout, input, output
  // watch out for:
  // - used by only an assignment
  // - used only by another module
  // - used only as port of super module
  // - element of a struct/array
  // - connects to element of struct/array
  // - reserved/renameable names

  late final Logic outTopA;
  late final LogicArray outArrTopA;
  late final Logic outStructTopA;

  late final Logic outTopB;
  late final LogicArray outArrTopB;
  late final Logic outStructTopB;

  late final Logic outTopC;
  late final LogicArray outArrTopC;
  late final Logic outStructTopC;

  //TODO: what about IO arrays and IO structs?

  TopWithUnusedSubModPorts({
    required Logic topIn,
    required LogicNet topIo,
    required LogicNet outTopIoA,
    required LogicNet outTopIoB,
    required LogicNet outTopIoC,
    required LogicArray topArrIn,
    required SimpleStruct topStructIn,
    required Naming? internalNaming, // TODO: loop over incl null
  }) : super(name: 'TopWithUnusedSubModPorts') {
    // Connectivity description:
    //                 ^ outTopA
    //                 |      between
    // topIn ---> [ SubModA ] -------> [ SubModB ] ---> outTopB
    //                 |-------------> [ SubModC ] ---> outTopC

    topIn = addInput('topIn', topIn, width: topIn.width);
    topIo = addInOut('topIo', topIo, width: topIo.width);
    topArrIn = addInputArray('topArrIn', topArrIn,
        elementWidth: topArrIn.elementWidth, dimensions: topArrIn.dimensions);
    topStructIn = addTypedInput('topStructIn', topStructIn);

    outTopIoA = addInOut('outTopIoA', outTopIoA, width: outTopIoA.width);
    outTopIoB = addInOut('outTopIoB', outTopIoB, width: outTopIoB.width);
    outTopIoC = addInOut('outTopIoC', outTopIoC, width: outTopIoC.width);

    final inpNotUsed = Logic(name: 'inpNotUsed', naming: internalNaming);
    final ioNotUsedA = LogicNet(name: 'ioNotUsedA', naming: internalNaming);
    final arrInNotUsed =
        LogicArray([4, 3], 2, name: 'arrInNotUsed', naming: internalNaming);
    final structInNotUsed =
        SimpleStruct(name: 'structInNotUsed', elementNaming: internalNaming);

    final betweenAtoBNet = LogicNet(
        name: 'betweenAtoBNet', width: outTopIoA.width, naming: internalNaming);

    final subModA = SubModWithSomePortsUsed(
      fromIn: topIn,
      fromIo: topIo,
      fromArrIn: topArrIn,
      fromStructIn: topStructIn,
      inpNotUsed: inpNotUsed,
      ioNotUsed: ioNotUsedA,
      arrInNotUsed: arrInNotUsed,
      structInNotUsed: structInNotUsed,
      outIoTo: outTopIoA,
      name: 'subModA',
    );

    outTopA = addOutput('outTopA', width: topIn.width)..gets(subModA.outTo);
    outArrTopA = addOutputArray('outArrTopA',
        elementWidth: topArrIn.elementWidth, dimensions: topArrIn.dimensions)
      ..gets(subModA.outArrTo);
    outStructTopA = addTypedOutput('outStructTopA', topStructIn.clone)
      ..gets(subModA.outStructTo);

    final subModB = SubModWithSomePortsUsed(
      fromIn: subModA.outTo,
      fromIo: betweenAtoBNet,
      fromArrIn: subModA.outArrTo.elements[0] as LogicArray,
      fromStructIn: subModA.outStructTo.elements[0],
      inpNotUsed: inpNotUsed,
      ioNotUsed: LogicNet(
          name: 'ioNotUsedB',
          naming: internalNaming), // don't multiply connect IO
      arrInNotUsed: arrInNotUsed,
      structInNotUsed: structInNotUsed,
      outIoTo: outTopIoB,
      name: 'subModB',
    );

    outTopB = addOutput('outTopB', width: topIn.width)..gets(subModB.outTo);
    outArrTopB = addOutputArray('outArrTopB',
        elementWidth: subModB.outArrTo.elementWidth,
        dimensions: subModB.outArrTo.dimensions)
      ..gets(subModB.outArrTo);
    outStructTopB = addTypedOutput('outStructTopB', subModB.outStructTo.clone)
      ..gets(subModB.outStructTo);

    final subModC = SubModWithSomePortsUsed(
      fromIn: subModA.outTo,
      fromIo: betweenAtoBNet,
      fromArrIn: LogicArray(
          [2, ...subModA.outArrTo.dimensions], subModA.outArrTo.elementWidth)
        ..elements[0].gets(subModA.outArrTo)
        ..elements[1].gets(Const(3, width: subModA.outArrTo.width)),
      fromStructIn: LogicStructure([
        SimpleStruct(elementNaming: internalNaming)..gets(subModA.outStructTo),
        SimpleStruct(elementNaming: internalNaming)
          ..gets(Const(3, width: subModA.outStructTo.width))
      ]),
      inpNotUsed: inpNotUsed,
      ioNotUsed: LogicNet(
          name: 'ioNotUsedC',
          naming: internalNaming), // don't multiply connect IO
      arrInNotUsed: arrInNotUsed,
      structInNotUsed: structInNotUsed,
      outIoTo: outTopIoC,
      name: 'subModC',
    );

    outTopC = addOutput('outTopC', width: topIn.width)..gets(subModC.outTo);
    outArrTopC = addOutputArray('outArrTopC',
        elementWidth: subModC.outArrTo.elementWidth,
        dimensions: subModC.outArrTo.dimensions)
      ..gets(subModC.outArrTo);
    outStructTopC = addTypedOutput('outStructTopC', subModC.outStructTo.clone)
      ..gets(subModC.outStructTo);

    if (internalNaming != null) {
      Logic(
              name: 'outNotUsed',
              width: subModA.outNotUsed.width,
              naming: internalNaming) <=
          subModA.outNotUsed;

      LogicArray(subModA.outArrNotUsed.dimensions,
              subModA.outArrNotUsed.elementWidth,
              name: 'outArrNotUsed', naming: internalNaming) <=
          subModA.outArrNotUsed;

      SimpleStruct(name: 'outStructNotUsed', elementNaming: internalNaming) <=
          subModA.outStructNotUsed;
    }
  }
}

class SubModWithSomePortsUsed extends Module {
  late final Logic outTo;
  late final LogicArray outArrTo;
  late final Logic outStructTo;

  late final Logic outNotUsed;
  late final LogicArray outArrNotUsed;
  late final SimpleStruct outStructNotUsed;

  SubModWithSomePortsUsed(
      {required Logic fromIn,
      required LogicNet fromIo,
      required LogicArray fromArrIn,
      required Logic fromStructIn,
      required Logic inpNotUsed,
      required LogicNet ioNotUsed,
      required LogicArray arrInNotUsed,
      required SimpleStruct structInNotUsed,
      required LogicNet outIoTo,
      required super.name})
      : super(definitionName: name.toUpperCase()) {
    fromIn = addInput('fromIn', fromIn, width: fromIn.width);
    fromIo = addInOut('fromIo', fromIo, width: fromIo.width);
    fromArrIn = addInputArray('fromArrIn', fromArrIn,
        elementWidth: fromArrIn.elementWidth, dimensions: fromArrIn.dimensions);
    fromStructIn = addTypedInput('fromStructIn', fromStructIn);

    inpNotUsed = addInput('inpNotUsed', inpNotUsed, width: inpNotUsed.width);
    ioNotUsed = addInOut('ioNotUsed', ioNotUsed, width: ioNotUsed.width);
    arrInNotUsed = addInputArray('arrInNotUsed', arrInNotUsed,
        elementWidth: arrInNotUsed.elementWidth,
        dimensions: arrInNotUsed.dimensions);
    structInNotUsed = addTypedInput('structInNotUsed', structInNotUsed);

    outTo = addOutput('outTo', width: fromIn.width)..gets(fromIn);
    outArrTo = addOutputArray('outArrTo',
        elementWidth: fromArrIn.elementWidth, dimensions: fromArrIn.dimensions)
      ..gets(fromArrIn);
    outStructTo = addTypedOutput('outStructTo', fromStructIn.clone)
      ..gets(fromStructIn);
    outIoTo = addInOut('outIoTo', outIoTo, width: fromIo.width)..gets(fromIo);

    outNotUsed = addOutput('outNotUsed', width: inpNotUsed.width)..gets(fromIn);
    outArrNotUsed = addOutputArray('outArrNotUsed',
        elementWidth: fromArrIn.elementWidth, dimensions: fromArrIn.dimensions);
    outStructNotUsed =
        addTypedOutput('outStructNotUsed', structInNotUsed.clone);
  }
}

/// This is for legacy deprecated testing.
// ignore: deprecated_member_use_from_same_package
class SubCustomSv extends Module with CustomSystemVerilog {
  final bool banExpressions;

  @override
  List<String> get expressionlessInputs =>
      banExpressions ? inputs.keys.toList() : const [];

  SubCustomSv(List<Logic> toSwizzle, {this.banExpressions = false}) {
    addInput('fer_swizzle', toSwizzle.swizzle(), width: toSwizzle.length);
  }

  @override
  String instantiationVerilog(String instanceType, String instanceName,
          Map<String, String> inputs, Map<String, String> outputs) =>
      '''
logic my_fancy_new_signal; // $instanceName (of type $instanceType)
assign my_fancy_new_signal <= ^${inputs['fer_swizzle']};
''';
}

class SubSv extends Module with SystemVerilog {
  final bool banExpressions;

  @override
  List<String> get expressionlessInputs =>
      banExpressions ? inputs.keys.toList() : const [];

  SubSv(List<Logic> toSwizzle, {this.banExpressions = false}) {
    addInput('fer_swizzle', toSwizzle.swizzle(), width: toSwizzle.length);
  }

  @override
  String instantiationVerilog(String instanceType, String instanceName,
          Map<String, String> ports) =>
      '''
logic my_fancy_new_signal; // $instanceName (of type $instanceType)
assign my_fancy_new_signal <= ^${ports['fer_swizzle']};
''';
}

class CustomDefinitionModule extends Module with SystemVerilog {
  late final Logic b;
  CustomDefinitionModule(Logic a) {
    a = addInput('a', a);
    b = addOutput('b')..gets(a);
  }

  @override
  String? instantiationVerilog(String instanceType, String instanceName,
          Map<String, String> ports) =>
      null;

  @override
  String? definitionVerilog(String definitionType) => '''
module $definitionType (
  input logic a,
  output logic b
);
// this is a custom definition!
assign b = a;
endmodule
''';
}

class TopWithCustomDef extends Module {
  TopWithCustomDef(Logic a) {
    a = addInput('a', a);
    final sub = CustomDefinitionModule(a);
    addOutput('b') <= sub.b;
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('signal declaration order', () {
    void checkSignalDeclarationOrder(String sv, List<String> signalNames) {
      final expected =
          signalNames.map((e) => RegExp(r'logic\s*\[?[:\d\s]*]?\s*' + e));
      final indices = expected.map(sv.indexOf);
      expect(indices.isSorted((a, b) => a.compareTo(b)), isTrue,
          reason: 'Expected order $signalNames, but indices were $indices');
    }

    test('input, output, and internal signals are sorted', () async {
      final mod = AlphabeticalModule(Logic(), Logic(), Logic());
      await mod.build();
      final sv = mod.generateSynth();

      // as instantiated
      checkSignalDeclarationOrder(sv, ['l', 'a', 'w']);
      checkSignalDeclarationOrder(sv, ['m', 'x', 'b']);

      // alphabetized
      checkSignalDeclarationOrder(sv, ['c', 'o', 'y']);

      checkSignalDeclarationOrder(
          sv, ['l', 'a', 'w', 'm', 'x', 'b', 'c', 'o', 'y']);
    });

    test('input, output, and internal signals are sorted (different widths)',
        () async {
      final mod = AlphabeticalWidthsModule();
      await mod.build();
      final sv = mod.generateSynth();

      // as instantiated
      checkSignalDeclarationOrder(sv, ['l', 'a', 'w']);
      checkSignalDeclarationOrder(sv, ['m', 'x', 'b']);

      // alphabetized
      checkSignalDeclarationOrder(sv, ['c', 'o', 'y']);

      checkSignalDeclarationOrder(
          sv, ['l', 'a', 'w', 'm', 'x', 'b', 'c', 'o', 'y']);
    });
  });

  test(
      'submodule port connections input, '
      'output are sorted by declaration order', () async {
    void checkPortConnectionOrder(String sv, List<String> signalNames) {
      final expected = signalNames.map((e) => '.$e($e)');
      final indices = expected.map(sv.indexOf);
      expect(indices.isSorted((a, b) => a.compareTo(b)), isTrue,
          reason: 'Expected order $signalNames, but indices were $indices');
    }

    final mod = AlphabeticalSubmodulePorts();
    await mod.build();
    final sv = mod.generateSynth();

    checkPortConnectionOrder(sv, ['l', 'a', 'w', 'm', 'x', 'b']);
  });

  test('expressions in sub-module declaration', () async {
    final mod = TopWithExpressions(Logic(), Logic(width: 5));
    await mod.build();

    final sv = mod.generateSynth();

    expect(sv, contains('.a((a | (b[2])))'));
  });

  test('no floating assignments', () async {
    final mod = ModuleWithFloatingSignals();
    await mod.build();

    final sv = mod.generateSynth();

    // only expect 1 assignment to xylophone
    expect('assign'.allMatches(sv).length, 1);
    expect('assign xylophone'.allMatches(sv).length, 1);
  });

  group('properly drops in custom systemverilog', () {
    for (final useOld in [true, false]) {
      for (final banExpressions in [true, false]) {
        test('(useOld=$useOld, banExpressions=$banExpressions)', () async {
          final mod = TopCustomSvWrap(Logic(), Logic(),
              useOld: useOld, banExpressions: banExpressions);
          await mod.build();
          final sv = mod.generateSynth();

          if (banExpressions) {
            expect(sv, contains('assign my_fancy_new_signal <= ^fer_swizzle;'));
          } else {
            expect(sv, contains('assign my_fancy_new_signal <= ^({a,b});'));
          }
        });
      }
    }
  });

  test('custom definition', () async {
    final mod = TopWithCustomDef(Logic());
    await mod.build();
    final sv = mod.generateSynth();

    expect(sv, contains('module CustomDefinitionModule ('));
    expect(sv, contains('// this is a custom definition!'));

    final vectors = [
      Vector({'a': 1}, {'b': 1}),
      Vector({'a': 0}, {'b': 0}),
    ];

    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  group('connected ports left unconnected', () {
    for (final naming in Naming.values) {
      test('with naming $naming', () async {
        final mod = TopWithUnusedSubModPorts(
          topIn: Logic(),
          topIo: LogicNet(width: 2),
          topArrIn: LogicArray([4, 3], 2),
          topStructIn: SimpleStruct(elementNaming: naming),
          internalNaming: naming,
          outTopIoA: LogicNet(width: 2),
          outTopIoB: LogicNet(width: 2),
          outTopIoC: LogicNet(width: 2),
        );
        await mod.build();
        final sv = mod.generateSynth();

        // print(sv);

        // TODO: checks:
        // - no assign statements with notUsed
        // - the notUsed ports have () on mergeable, actual things on renameable
        // - net across 2 modules is maintained, individual net is not
        // - arrays and structss

        File('tmp_${naming.name}.sv').writeAsStringSync(sv);

        final vectors = [
          Vector({
            'topIn': 1,
            'topArrIn': LogicValue.of('110011').replicate(4),
            'topStructIn': LogicValue.of('110011110011'),
            //TODO: dont forget inouts!
          }, {
            'outTopA': 1,
            'outTopB': 1,
            'outTopC': 1,
            'outArrTopA': LogicValue.of('110011').replicate(4),
            'outArrTopB': LogicValue.of('110011'),
            'outArrTopC': [
              LogicValue.ofInt(3, 24),
              LogicValue.of('110011').replicate(4)
            ].swizzle(),
            'outStructTopA': LogicValue.of('110011110011'),
            'outStructTopB': LogicValue.of('0011'),
            'outStructTopC': [
              LogicValue.ofInt(
                3,
                12,
              ),
              LogicValue.of('110011110011')
            ].swizzle(),
          }),
        ];

        await SimCompare.checkFunctionalVector(mod, vectors);
        SimCompare.checkIverilogVector(mod, vectors);
      });
    }
  });
}
