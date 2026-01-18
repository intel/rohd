// Copyright (C) 2023-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// sv_gen_test.dart
// Tests for SystemVerilog generation.
//
// 2023 October 4
// Author: Max Korbel <max.korbel@intel.com>

import 'package:collection/collection.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:rohd/src/utilities/sv_cleaner.dart';
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
  final bool asNet;

  SimpleStruct(
      {required this.elementNaming,
      super.name = 'SimpleStruct',
      this.asNet = false})
      : super([
          (asNet ? LogicNet.new : Logic.new)(
              name: 'field4', width: 4, naming: elementNaming),
          (asNet ? LogicNet.new : Logic.new)(
              name: 'field8', width: 8, naming: elementNaming),
        ]);

  @override
  SimpleStruct clone({String? name}) => SimpleStruct(
      name: name ?? this.name, elementNaming: elementNaming, asNet: asNet);
}

class ModWithUselessWireMods extends Module {
  ModWithUselessWireMods() {
    final a = addInput('a', Logic(width: 8), width: 8);
    final b = addInput('b', Logic(width: 8), width: 8);

    // none of these should show up, unused stuff
    [a, b].swizzle();
    b.replicate(3);
    a.getRange(2, 6);
  }
}

class TopWithUnusedSubModPorts extends Module {
  late final Logic outTopA;
  late final LogicArray outArrTopA;
  late final Logic outStructTopA;

  late final Logic outTopB;
  late final LogicArray outArrTopB;
  late final Logic outStructTopB;

  late final Logic outTopC;
  late final LogicArray outArrTopC;
  late final Logic outStructTopC;

  TopWithUnusedSubModPorts({
    required Logic topIn,
    required LogicNet topIo,
    required LogicNet outTopIoA,
    required LogicNet outTopIoB,
    required LogicNet outTopIoC,
    required LogicArray topArrIn,
    required SimpleStruct topStructIn,
    required LogicArray topArrNetIn,
    required SimpleStruct topStructNetIn,
    required LogicArray outTopIoArrA,
    required SimpleStruct outTopIoStructA,
    required Naming internalNaming,
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
    topArrNetIn = addInOutArray('topArrNetIn', topArrNetIn,
        elementWidth: topArrNetIn.elementWidth,
        dimensions: topArrNetIn.dimensions);
    topStructNetIn = addTypedInOut('topStructNetIn', topStructNetIn);

    outTopIoA = addInOut('outTopIoA', outTopIoA, width: outTopIoA.width);
    outTopIoB = addInOut('outTopIoB', outTopIoB, width: outTopIoB.width);
    outTopIoC = addInOut('outTopIoC', outTopIoC, width: outTopIoC.width);

    outTopIoArrA = addInOutArray('outTopIoArrA', outTopIoArrA,
        elementWidth: outTopIoArrA.elementWidth,
        dimensions: outTopIoArrA.dimensions);
    outTopIoStructA = addTypedInOut('outTopIoStructA', outTopIoStructA);

    final inpNotUsed = Logic(name: 'inpNotUsed', naming: internalNaming);
    final ioNotUsedA = LogicNet(name: 'ioNotUsedA', naming: internalNaming);
    final arrInNotUsed =
        LogicArray([4, 3], 2, name: 'arrInNotUsed', naming: internalNaming);
    final structInNotUsed =
        SimpleStruct(name: 'structInNotUsed', elementNaming: internalNaming);
    final arrNetInNotUsed = LogicArray.net([2, 2], 3,
        name: 'arrNetInNotUsed', naming: internalNaming);
    final structNetInNotUsed = SimpleStruct(
        name: 'structNetInNotUsed', elementNaming: internalNaming, asNet: true);

    final betweenAtoBNet = LogicNet(
        name: 'betweenAtoBNet', width: outTopIoA.width, naming: internalNaming);
    final betweenAtoBArrNet = LogicArray.net(
        name: 'betweenAtoBArrNet',
        outTopIoArrA.dimensions,
        outTopIoArrA.elementWidth,
        naming: internalNaming);
    final betweenAtoBStructNet = outTopIoStructA.clone(
        name: internalNaming == Naming.renameable
            ? 'betweenAtoBStructNet'
            : null);

    final subModA = SubModWithSomePortsUsed(
      fromIn: topIn,
      fromIo: topIo,
      fromArrIn: topArrIn,
      fromStructIn: topStructIn,
      fromArrNetIn: topArrNetIn,
      fromStructNetIn: topStructNetIn,
      inpNotUsed: inpNotUsed,
      ioNotUsed: ioNotUsedA,
      arrInNotUsed: arrInNotUsed,
      structInNotUsed: structInNotUsed,
      arrNetInNotUsed: arrNetInNotUsed,
      structNetInNotUsed: structNetInNotUsed,
      outIoTo: outTopIoA,
      outIoArrTo: outTopIoArrA,
      outIoStructTo: outTopIoStructA,
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
      fromArrNetIn: topArrNetIn,
      fromStructNetIn: topStructNetIn,
      inpNotUsed: inpNotUsed,
      ioNotUsed: LogicNet(
          name: 'ioNotUsedB',
          naming: internalNaming), // don't multiply connect IO
      arrInNotUsed: arrInNotUsed,
      structInNotUsed: structInNotUsed,
      arrNetInNotUsed: arrNetInNotUsed.clone(),
      structNetInNotUsed: structNetInNotUsed.clone(),
      outIoTo: outTopIoB,
      outIoArrTo: betweenAtoBArrNet,
      outIoStructTo: betweenAtoBStructNet,
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
      fromArrNetIn: topArrNetIn,
      fromStructNetIn: topStructNetIn,
      inpNotUsed: inpNotUsed,
      ioNotUsed: LogicNet(
          name: 'ioNotUsedC',
          naming: internalNaming), // don't multiply connect IO
      arrInNotUsed: arrInNotUsed,
      structInNotUsed: structInNotUsed,
      arrNetInNotUsed: arrNetInNotUsed.clone(),
      structNetInNotUsed: structNetInNotUsed.clone(),
      outIoTo: outTopIoC,
      outIoArrTo: betweenAtoBArrNet,
      outIoStructTo: betweenAtoBStructNet,
      name: 'subModC',
    );

    outTopC = addOutput('outTopC', width: topIn.width)..gets(subModC.outTo);
    outArrTopC = addOutputArray('outArrTopC',
        elementWidth: subModC.outArrTo.elementWidth,
        dimensions: subModC.outArrTo.dimensions)
      ..gets(subModC.outArrTo);
    outStructTopC = addTypedOutput('outStructTopC', subModC.outStructTo.clone)
      ..gets(subModC.outStructTo);

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
      required LogicArray fromArrNetIn,
      required SimpleStruct fromStructNetIn,
      required Logic inpNotUsed,
      required LogicNet ioNotUsed,
      required LogicArray arrInNotUsed,
      required SimpleStruct structInNotUsed,
      required LogicArray arrNetInNotUsed,
      required SimpleStruct structNetInNotUsed,
      required LogicNet outIoTo,
      required LogicArray outIoArrTo,
      required SimpleStruct outIoStructTo,
      required super.name})
      : super(definitionName: name.toUpperCase()) {
    fromIn = addInput('fromIn', fromIn, width: fromIn.width);
    fromIo = addInOut('fromIo', fromIo, width: fromIo.width);
    fromArrIn = addInputArray('fromArrIn', fromArrIn,
        elementWidth: fromArrIn.elementWidth, dimensions: fromArrIn.dimensions);
    fromStructIn = addTypedInput('fromStructIn', fromStructIn);
    fromArrNetIn = addInOutArray('fromArrNetIn', fromArrNetIn,
        elementWidth: fromArrNetIn.elementWidth,
        dimensions: fromArrNetIn.dimensions);
    fromStructNetIn = addTypedInOut('fromStructNetIn', fromStructNetIn);

    inpNotUsed = addInput('inpNotUsed', inpNotUsed, width: inpNotUsed.width);
    ioNotUsed = addInOut('ioNotUsed', ioNotUsed, width: ioNotUsed.width);
    arrInNotUsed = addInputArray('arrInNotUsed', arrInNotUsed,
        elementWidth: arrInNotUsed.elementWidth,
        dimensions: arrInNotUsed.dimensions);
    structInNotUsed = addTypedInput('structInNotUsed', structInNotUsed);
    arrNetInNotUsed = addInOutArray('arrNetInNotUsed', arrNetInNotUsed,
        elementWidth: arrNetInNotUsed.elementWidth,
        dimensions: arrNetInNotUsed.dimensions);
    structNetInNotUsed =
        addTypedInOut('structNetInNotUsed', structNetInNotUsed);

    outTo = addOutput('outTo', width: fromIn.width)..gets(fromIn);
    outArrTo = addOutputArray('outArrTo',
        elementWidth: fromArrIn.elementWidth, dimensions: fromArrIn.dimensions)
      ..gets(fromArrIn);
    outStructTo = addTypedOutput('outStructTo', fromStructIn.clone)
      ..gets(fromStructIn);
    outIoTo = addInOut('outIoTo', outIoTo, width: fromIo.width)..gets(fromIo);
    outIoArrTo = addInOutArray('outIoArrTo', outIoArrTo,
        elementWidth: outIoArrTo.elementWidth,
        dimensions: outIoArrTo.dimensions)
      ..gets(fromArrNetIn);
    outIoStructTo = addTypedInOut('outIoStructTo', outIoStructTo)
      ..gets(fromStructNetIn);

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

  @override
  final bool acceptsEmptyPortConnections;

  CustomDefinitionModule(Logic a, {this.acceptsEmptyPortConnections = false}) {
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

class ModuleWithCustomDefinitionEmptyPorts extends Module {
  ModuleWithCustomDefinitionEmptyPorts(Logic a,
      {bool acceptsEmptyPortConnections = false}) {
    a = addInput('a', a);
    CustomDefinitionModule(a,
        acceptsEmptyPortConnections: acceptsEmptyPortConnections);
  }
}

class TopWithCustomDef extends Module {
  TopWithCustomDef(Logic a) {
    a = addInput('a', a);
    final sub = CustomDefinitionModule(a);
    addOutput('b') <= sub.b;
  }
}

class ModWithPartialArrayAssignment extends Module {
  ModWithPartialArrayAssignment(Logic a) {
    a = addInput('a', a, width: 8);

    final aArr = LogicArray([2], 8, name: 'aArr');
    aArr.elements[0] <= a;

    final b = addOutput('b', width: 8);

    b <= aArr.elements[0];
  }
}

class ModWithConstInlineUnaryOp extends Module {
  ModWithConstInlineUnaryOp() {
    addOutput('b', width: 8) <= ~Const(0, width: 8);
  }
}

class TieOffSubsetTop extends Module {
  LogicArray get outApple => output('outApple') as LogicArray;
  LogicArray get outBanana => output('outBanana') as LogicArray;

  TieOffSubsetTop(Logic clk, {required bool withRedirect}) {
    clk = addInput('clk', clk);

    var tieoffApple =
        Const(0, width: 2).named('apple_tieoff', naming: Naming.mergeable);

    final apple = LogicArray([4], 4, name: 'apple');

    if (withRedirect) {
      tieoffApple = Logic(width: 2)..gets(tieoffApple);
    }

    apple.elements[1].assignSubset(tieoffApple.elements, start: 1);

    final submod = TieOffSubsetSub(clk, apple, withRedirect: withRedirect);

    addOutputArray('outApple', dimensions: [4], elementWidth: 4).gets(apple);
    addOutputArray('outBanana', dimensions: [4], elementWidth: 4)
        .gets(submod.outBanana);
  }
}

class TieOffSubsetSub extends Module {
  LogicArray get outBanana => output('banana') as LogicArray;

  TieOffSubsetSub(Logic clk, Logic apple, {required bool withRedirect})
      : super(name: 'submod') {
    apple = addInputArray('apple', apple, dimensions: [4], elementWidth: 4);
    clk = addInput('clk', clk);

    var tieoffBanana =
        Const(0, width: 2).named('banana_tieoff', naming: Naming.mergeable);

    if (withRedirect) {
      tieoffBanana = Logic(width: 2)..gets(tieoffBanana);
    }

    final banana = addOutputArray('banana', dimensions: [4], elementWidth: 4);

    banana.elements[1].assignSubset(tieoffBanana.elements, start: 1);
  }
}

class TieOffPortTop extends Module {
  TieOffPortTop(Logic clk, {required bool withRedirect}) {
    clk = addInput('clk', clk);

    var tieoffApple = Const(0).named('apple_tieoff', naming: Naming.mergeable);

    final apple = Logic(name: 'apple', naming: Naming.mergeable);

    if (withRedirect) {
      tieoffApple = Logic()..gets(tieoffApple);
    }

    apple <= tieoffApple;

    final submod = TieOffPortSub(apple, withRedirect: withRedirect);

    addOutput('outApple') <= submod.outApple;
    addOutput('outBanana') <= submod.banana;
  }
}

class TieOffPortSub extends Module {
  late final Logic banana;
  late final Logic outApple;
  TieOffPortSub(Logic apple, {required bool withRedirect}) {
    apple = addInput('apple', apple);

    var tieoffBanana =
        Const(0).named('banana_tieoff', naming: Naming.mergeable);

    if (withRedirect) {
      tieoffBanana = Logic()..gets(tieoffBanana);
    }

    banana = addOutput('banana');
    outApple = addOutput('outApple')..gets(apple);

    banana <= tieoffBanana;
  }
}

class OutToInOutTop extends Module {
  OutToInOutTop(Logic clk) : super(name: 'out_to_inout_top') {
    clk = addInput('clk', clk);
    final modWithOut = ModWithOut(clk);
    final myNetTop = LogicNet();
    myNetTop <= modWithOut.myOut;

    addOutput('clkB') <= ModWithInOut(myNetTop).clkB;
  }
}

class ModWithOut extends Module {
  late final Logic myOut;

  ModWithOut(Logic clk) : super(name: 'mod_with_out') {
    clk = addInput('clk', clk);
    myOut = addOutput('myOut')..gets(~clk);
  }
}

class ModWithInOut extends Module {
  late final Logic clkB;
  ModWithInOut(LogicNet myNet) : super(name: 'mod_with_inout') {
    myNet = addInOut('myNet', myNet);

    clkB = addOutput('clkB')..gets(myNet);
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  test('const unary inline op', () async {
    final mod = ModWithConstInlineUnaryOp();
    await mod.build();

    final vectors = [
      Vector({}, {'b': 0xff}),
    ];

    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  group('tieoff ', () {
    for (final redirect in [true, false]) {
      group('with redirect=$redirect', () {
        test('subset of array', () async {
          final mod = TieOffSubsetTop(Logic(), withRedirect: redirect);
          await mod.build();

          final sv = mod.generateSynth();

          expect(sv, contains("assign banana_tieoff = 2'h0;"));
          expect(sv, contains("assign apple_tieoff = 2'h0;"));

          // simcompare to make sure simulation works as expected
          final vectors = [
            Vector({}, {
              'outApple': 'zzzzzzzzz00zzzzz',
              'outBanana': 'zzzzzzzzz00zzzzz',
            }),
          ];

          await SimCompare.checkFunctionalVector(mod, vectors);
          SimCompare.checkIverilogVector(mod, vectors);
        });

        test('full port', () async {
          final mod = TieOffPortTop(Logic(), withRedirect: redirect);
          await mod.build();

          final sv = mod.generateSynth();

          expect(sv, contains("assign banana = 1'h0;"));
          expect(sv, contains(".apple(1'h0)"));

          // simcompare to make sure simulation works as expected
          final vectors = [
            Vector({}, {
              'outApple': 0,
              'outBanana': 0,
            }),
          ];

          await SimCompare.checkFunctionalVector(mod, vectors);
          SimCompare.checkIverilogVector(mod, vectors);
        });
      });
    }
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
          final sv =
              SvCleaner.removeSwizzleAnnotationComments(mod.generateSynth());

          if (banExpressions) {
            expect(sv, contains('assign my_fancy_new_signal <= ^fer_swizzle;'));
          } else {
            expect(sv, contains('assign my_fancy_new_signal <= ^({a,b});'));
          }
        });
      }
    }
  });

  group('custom definition empty port connections', () {
    for (final acceptsEmptyPortConnections in [true, false]) {
      test('acceptsEmptyPortConnections=$acceptsEmptyPortConnections',
          () async {
        final mod = ModuleWithCustomDefinitionEmptyPorts(Logic(),
            acceptsEmptyPortConnections: acceptsEmptyPortConnections);
        await mod.build();
        final sv = mod.generateSynth();

        if (acceptsEmptyPortConnections) {
          expect(sv, contains('.b()'));
        } else {
          expect(sv, isNot(contains('.b()')));
          expect(sv, contains('.b(b)'));
        }
      });
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

  test('unused wire mods are pruned', () async {
    final mod = ModWithUselessWireMods();
    await mod.build();

    final sv = mod.generateSynth();

    expect(sv, isNot(contains('swizzle')));
    expect(sv, isNot(contains('replicate')));
    expect(sv, isNot(contains('subset')));

    expect(sv, contains('''
module ModWithUselessWireMods (
input logic [7:0] a,
input logic [7:0] b
);

endmodule : ModWithUselessWireMods'''));
  });

  test('partial array assignment sv', () async {
    final mod = ModWithPartialArrayAssignment(Logic(width: 8));
    await mod.build();
    final sv = mod.generateSynth();

    expect(sv, contains('assign b = aArr[0];'));
    expect(sv, contains('assign aArr[0] = a;'));
    expect(sv, isNot(contains('aArr[1]')));

    final vectors = [
      Vector({'a': 42}, {'b': 42}),
      Vector({'a': 255}, {'b': 255}),
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  group('connected ports and pruning', () {
    for (final naming in [Naming.renameable, Naming.mergeable]) {
      test('with naming $naming', () async {
        final mod = TopWithUnusedSubModPorts(
          topIn: Logic(),
          topIo: LogicNet(width: 2),
          topArrIn: LogicArray([4, 3], 2),
          topStructIn: SimpleStruct(elementNaming: naming),
          topArrNetIn: LogicArray.net([2, 2], 3),
          topStructNetIn: SimpleStruct(elementNaming: naming, asNet: true),
          internalNaming: naming,
          outTopIoA: LogicNet(width: 2),
          outTopIoB: LogicNet(width: 2),
          outTopIoC: LogicNet(width: 2),
          outTopIoArrA: LogicArray.net([2, 2], 3),
          outTopIoStructA: SimpleStruct(elementNaming: naming, asNet: true),
        );
        await mod.build();

        final topSv = SynthBuilder(mod, SystemVerilogSynthesizer())
            .synthesisResults
            .firstWhere((e) => e.module is TopWithUnusedSubModPorts)
            .toSynthFileContents()
            .first
            .contents;

        if (naming == Naming.mergeable) {
          // make sure we don't see any NotUsed we dont expect
          expect(topSv,
              isNot(contains(RegExp('assign.*NotUsed', caseSensitive: false))),
              reason: 'No assignments with unused signals');
          expect(
              topSv,
              isNot(contains(
                  RegExp('net_connect.*NotUsed', caseSensitive: false))),
              reason: 'No net assignments with unused signals');
          expect(topSv,
              isNot(contains(RegExp('logic.*NotUsed', caseSensitive: false))),
              reason: 'No declarations with unused signals');
          expect(topSv,
              isNot(contains(RegExp('NotUsed[^(]', caseSensitive: false))),
              reason: 'NotUsed should only appear when followed by ()');

          expect('.fromIo(fromIo),'.allMatches(topSv).length, 2,
              reason: 'The fromIo port should be connected'
                  ' in both subModB and subModC');
          expect('.outIoArrTo(outIoArrTo),'.allMatches(topSv).length, 2,
              reason: 'The outIoArrTo port should be connected'
                  ' in both subModB and subModC');
        } else if (naming == Naming.renameable) {
          // make sure we see all the ones we expect still there
          expect(
              topSv, contains(RegExp(r'SUBMODA.*inpNotUsed\(inpNotUsed\),')));
          expect(topSv,
              contains(RegExp(r'SUBMODA.*arrInNotUsed\(arrInNotUsed\),')));
          expect(
              topSv,
              contains(
                  RegExp(r'SUBMODA.*structInNotUsed\(structInNotUsed\),')));
          expect(
              topSv, contains(RegExp(r'SUBMODA.*outNotUsed\(outNotUsed\),')));
          expect(topSv,
              contains(RegExp(r'SUBMODA.*outArrNotUsed\(outArrNotUsed\),')));
          expect(
              topSv,
              contains(
                  RegExp(r'SUBMODA.*outStructNotUsed\(outStructNotUsed\),')));
          expect(topSv, contains(RegExp(r'SUBMODA.*ioNotUsed\(ioNotUsedA\),')));

          expect('.fromIo(betweenAtoBNet),'.allMatches(topSv).length, 2,
              reason: 'The fromIo port should be connected'
                  ' in both subModB and subModC');
          expect('.outIoArrTo(betweenAtoBArrNet),'.allMatches(topSv).length, 2,
              reason: 'The outIoArrTo port should be connected'
                  ' in both subModB and subModC');
          expect(
              RegExp('net_connect.*betweenAtoBStructNet_field8')
                  .allMatches(topSv)
                  .length,
              2,
              reason: 'The outIoStructTo port should be connected'
                  ' in both subModB and subModC');
        }

        final vectors = [
          Vector({
            'topIn': 1,
            'topArrIn': LogicValue.of('110011').replicate(4),
            'topStructIn': LogicValue.of('110011110011'),
            'topIo': '10',
            'topArrNetIn': LogicValue.of('110011').replicate(2),
            'topStructNetIn': LogicValue.of('101011101010'),
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
            'outTopIoA': '10',
            'outTopIoArrA': LogicValue.of('110011').replicate(2),
            'outTopIoStructA': LogicValue.of('101011101010')
          }),
        ];

        await SimCompare.checkFunctionalVector(mod, vectors);
        SimCompare.checkIverilogVector(mod, vectors);
      });
    }
  });

  test('out to inout unnamed connection', () async {
    // this test makes sure we don't lose an unnamed connection from an output
    // to an inout

    final mod = OutToInOutTop(Logic());
    await mod.build();

    final sv = mod.generateSynth();

    expect(sv, contains('assign myNet = myOut;'));

    final vectors = [
      Vector({'clk': 0}, {'clkB': 1}),
      Vector({'clk': 1}, {'clkB': 0}),
    ];
    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });
}
