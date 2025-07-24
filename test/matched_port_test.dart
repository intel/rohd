// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// matched_port_test.dart
// Tests for matching ports on modules
//
// 2025 July
// Author: Max Korbel <max.korbel@intel.com>

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class MyStruct extends LogicStructure {
  final Logic ready;
  final Logic valid;

  final bool asNet;

  factory MyStruct({String? name, bool asNet = false}) => MyStruct._(
        (asNet ? LogicNet.new : Logic.new)(
            name: 'ready', naming: Naming.mergeable),
        (asNet ? LogicNet.new : Logic.new)(
            name: 'valid', naming: Naming.mergeable),
        name: name,
        asNet: asNet,
      );

  MyStruct._(this.ready, this.valid,
      {required String? name, required this.asNet})
      : super([ready, valid], name: name ?? 'myStruct');

  @override
  MyStruct clone({String? name}) =>
      MyStruct(name: name ?? this.name, asNet: asNet);
}

class SimpleStructModule extends Module {
  late final MyStruct myOut;

  SimpleStructModule(MyStruct myIn, {super.name = 'simple_struct_mod'}) {
    myIn = (myIn.isNet ? addMatchedInOut : addMatchedInput)('myIn', myIn);

    final internal = myIn.clone(name: 'internal_struct');
    internal.ready <= myIn.valid;
    internal.valid <= myIn.ready;

    if (myIn.isNet) {
      myOut = myIn.clone(name: 'myOutExt');
      addMatchedInOut('myOut', myOut) <= internal;
    } else {
      myOut = addMatchedOutput('myOut', internal)..gets(internal);
    }
  }
}

class SimpleStructModuleContainer extends Module {
  SimpleStructModuleContainer(Logic a1, Logic a2,
      {super.name = 'simple_struct_mod_container', bool asNet = false}) {
    final Logic Function(String, Logic) inMaker = asNet ? addInOut : addInput;
    // ignore: omit_local_variable_types
    final Logic Function(String name) outMaker = asNet
        ? (name) => addInOut(name, LogicNet(name: 'ext$name'))
        : addOutput;

    a1 = inMaker('a1', a1);
    a2 = inMaker('a2', a2);
    final upperStruct = MyStruct(name: 'upper_struct', asNet: asNet);
    upperStruct.ready <= a1;
    upperStruct.valid <= a2;
    final sub = SimpleStructModule(upperStruct);

    outMaker('b1') <= sub.myOut.ready;
    outMaker('b2') <= sub.myOut.valid;
  }
}

class DummyModule extends Module {}

class CloneNoNameStruct extends LogicStructure {
  CloneNoNameStruct({bool asNet = false})
      : super([if (asNet) LogicNet() else Logic()], name: 'abc');

  @override
  CloneNoNameStruct clone({String? name}) => CloneNoNameStruct();
}

class MatcherModule extends Module {
  final bool isNet;

  Logic get anyOut => isNet ? inOutSource('anyOut') : output('anyOut');

  @protected
  late final Logic _innerOut;

  @protected
  late final Logic _anyIn;

  MatcherModule(Logic anyIn) : isNet = anyIn.isNet {
    if (isNet) {
      _anyIn = addMatchedInOut('anyIn', anyIn);
      _innerOut = addMatchedInOut('anyOut', anyIn.clone());
    } else {
      _anyIn = addMatchedInput('anyIn', anyIn);
      _innerOut = addMatchedOutput('anyOut', _anyIn);
    }

    _makeLogic();
  }

  void _makeLogic() {
    _innerOut <= ~_anyIn;
  }
}

class MatcherModuleWrapper extends MatcherModule {
  MatcherModuleWrapper(super.anyIn);
  @override
  void _makeLogic() {
    _innerOut <= MatcherModule(_anyIn).anyOut;
  }
}

class MatcherPassThrough extends MatcherModule {
  MatcherPassThrough(super.anyIn);

  @override
  void _makeLogic() {
    _innerOut <= _anyIn;
  }
}

class PartialLogicNetStructAssignment extends Module {
  PartialLogicNetStructAssignment(MyStruct a) {
    a = addMatchedInOut('a', a);

    final b = addMatchedInOut('b', a.clone());

    b.valid <= a.valid;
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  test('simple struct module', () async {
    final mod = SimpleStructModuleContainer(Logic(), Logic());
    await mod.build();

    final sv = mod.generateSynth();

    expect(sv, isNot(contains('internal_struct')));

    expect(sv, contains('input logic [1:0] myIn'));
    expect(sv, contains('output logic [1:0] myOut'));

    final vectors = [
      Vector({'a1': 0, 'a2': 1}, {'b1': 1, 'b2': 0}),
      Vector({'a1': 1, 'a2': 0}, {'b1': 0, 'b2': 1}),
    ];

    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  test('matched array is an array', () async {
    final mod = MatcherPassThrough(LogicArray([4], 2));
    await mod.build();

    expect(mod.anyOut, isA<LogicArray>());

    final sv = mod.generateSynth();

    expect(sv, contains('input logic [3:0][1:0] anyIn'));
    expect(sv, contains('output logic [3:0][1:0] anyOut'));
    expect(sv, contains('assign anyOut = anyIn;'));
  });

  group('simple struct module with nets', () {
    Future<Module> makeMod() async {
      final mod =
          SimpleStructModuleContainer(LogicNet(), LogicNet(), asNet: true);
      await mod.build();

      final sv = mod.generateSynth();

      expect(sv, isNot(contains('internal_struct')));

      expect(sv, contains('inout wire [1:0] myIn'));
      expect(sv, contains('inout wire [1:0] myOut'));

      return mod;
    }

    test('forward', () async {
      final mod = await makeMod();

      final vectors = [
        Vector({'a1': 0, 'a2': 1}, {'b1': 1, 'b2': 0}),
        Vector({'a1': 1, 'a2': 0}, {'b1': 0, 'b2': 1}),
      ];

      await SimCompare.checkFunctionalVector(mod, vectors);
      SimCompare.checkIverilogVector(mod, vectors);
    });

    test('reversed', () async {
      final mod = await makeMod();

      final vectorsReversed = [
        Vector({'b1': 1, 'b2': 0}, {'a1': 0, 'a2': 1}),
        Vector({'b1': 0, 'b2': 1}, {'a1': 1, 'a2': 0}),
      ];

      await SimCompare.checkFunctionalVector(mod, vectorsReversed);
      SimCompare.checkIverilogVector(mod, vectorsReversed);
    });
  });

  group('illegal match port creations', () {
    final matchedPortCreators = {
      'input': (Logic logic) => DummyModule().addMatchedInput('p', logic),
      'output': (Logic logic) => DummyModule().addMatchedOutput('p', logic),
      'inOut': (Logic logic) => DummyModule().addMatchedInOut('p', logic),
    };

    group('struct with partial nets fails', () {
      for (final MapEntry(key: portType, value: creator)
          in matchedPortCreators.entries) {
        test(portType, () {
          expect(
            () => creator(LogicStructure([Logic(), LogicNet()])),
            throwsA(isA<PortTypeException>()),
          );
        });
      }
    });

    group('struct with missing clone name fails', () {
      for (final MapEntry(key: portType, value: creator)
          in matchedPortCreators.entries) {
        test(portType, () {
          try {
            creator(CloneNoNameStruct(asNet: portType == 'inOut'));
          } on PortTypeException catch (e) {
            expect(e.message, contains('failed to update the signal name'));
          }
        });
      }
    });
  });

  test('partial net struct assign', () async {
    final mod = PartialLogicNetStructAssignment(MyStruct(asNet: true));
    await mod.build();

    final vectors = [
      Vector({'a': 0}, {'b': '0z'}),
      Vector({'a': 3}, {'b': '1z'})
    ];

    await SimCompare.checkFunctionalVector(mod, vectors);
    SimCompare.checkIverilogVector(mod, vectors);
  });

  group('various port types to match', () {
    final portTypes = [
      (name: 'simple logic', maker: () => Logic(width: 8)),
      (name: 'logic array', maker: () => LogicArray([4], 2)),
      (name: 'deeper logic array', maker: () => LogicArray([1, 2, 2], 2)),
      (
        name: 'fancy mixed struct',
        maker: () => LogicStructure([
              Logic(width: 2),
              LogicArray([2], 2),
              LogicStructure([Logic(), Logic()])
            ])
      ),
      (name: 'logic net', maker: () => LogicNet(width: 8)),
      (name: 'logic array net', maker: () => LogicArray.net([2], 4)),
      (
        name: 'fancy logic struct net',
        maker: () => LogicStructure([
              LogicNet(),
              LogicNet(),
              LogicArray.net([4], 1),
              LogicStructure([LogicNet(width: 2)])
            ])
      ),
    ];

    final modMakers = [
      (name: 'basic', maker: MatcherModule.new, invert: true),
      (name: 'wrapper', maker: MatcherModuleWrapper.new, invert: true),
      (name: 'pass through', maker: MatcherPassThrough.new, invert: false),
    ];

    for (final modMaker in modMakers) {
      group('${modMaker.name} module', () {
        for (final portType in portTypes) {
          test(portType.name, () async {
            final mod = modMaker.maker(portType.maker());

            // check that things cloned up properly
            expect(mod.anyOut.runtimeType, portType.maker().runtimeType);

            await mod.build();

            final vectors = [
              Vector(
                  {'anyIn': 0xa5}, {'anyOut': modMaker.invert ? 0x5a : 0xa5}),
              Vector(
                  {'anyIn': 0xff}, {'anyOut': modMaker.invert ? 0x00 : 0xff}),
              Vector(
                  {'anyIn': 0x13}, {'anyOut': modMaker.invert ? 0xec : 0x13}),
            ];

            await SimCompare.checkFunctionalVector(mod, vectors);
            SimCompare.checkIverilogVector(mod, vectors);
          });
        }
      });
    }
  });
}
