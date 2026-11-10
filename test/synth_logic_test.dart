// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// synth_logic_test.dart
// Tests for synthesized signal aliases and metadata.
//
// 2026 November 9
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';
import 'package:test/test.dart';

class _SynthLogicTestModule extends Module {
  _SynthLogicTestModule() {
    addOutputArray('array', dimensions: [1], elementWidth: 8);
  }
}

class _CountingSynthLogic extends SynthLogic {
  int logicsReads = 0;

  _CountingSynthLogic(super.initialLogic,
      {required super.parentSynthModuleDefinition});

  @override
  List<Logic> get logics {
    logicsReads++;
    return super.logics;
  }
}

void main() {
  late SynthModuleDefinition definition;

  setUp(() async {
    final module = _SynthLogicTestModule();
    await module.build();
    definition = SynthModuleDefinition(module);
  });

  tearDown(() async {
    await Simulator.reset();
  });

  SynthLogic synth(Logic logic) =>
      SynthLogic(logic, parentSynthModuleDefinition: definition);

  // Repeated reads must not allocate another copy of the same aliases.
  test('alias snapshots are reused and read-only', () {
    final signal = synth(Logic(width: 8));
    for (var index = 0; index < 128; index++) {
      signal.adopt(synth(Logic(width: 8)));
    }

    final snapshots = Set<List<Logic>>.identity();
    for (var index = 0; index < 128; index++) {
      snapshots.add(signal.logics);
    }
    expect(snapshots.length, 1);
    expect(snapshots.single, hasLength(129));
    expect(snapshots.single.clear, throwsUnsupportedError);
  });

  // Merging changes the current snapshot, not snapshots already returned.
  test('merges preserve snapshot contents and naming priority', () {
    final unnamed = Logic(width: 8);
    final mergeable =
        Logic(name: 'mergeable', width: 8, naming: Naming.mergeable);
    final renameable = Logic(name: 'renameable', width: 8);
    final constant = Const(3, width: 8);
    final reserved = Logic(name: 'reserved', width: 8, naming: Naming.reserved);
    final signal = synth(unnamed);

    for (final alias in [mergeable, renameable, constant, reserved]) {
      final previous = signal.logics;
      final previousContents = List<Logic>.of(previous);
      signal.adopt(synth(alias), force: true);
      expect(previous, orderedEquals(previousContents));
      expect(signal.logics, isNot(same(previous)));
      expect(signal.logics, contains(alias));
      expect(signal.logics, same(signal.logics));
      expect(signal.firstLogic, same(signal.logics.first));
    }

    expect(signal.logics,
        orderedEquals([reserved, constant, renameable, mergeable, unnamed]));
    expect(signal.width, 8);
    expect(signal.isNet, isFalse);
  });

  // Forced element merges can retain an extra constant as a mergeable alias.
  test('forced array-element adoption invalidates every changed snapshot', () {
    final array = definition.module.output('array') as LogicArray;
    final element = definition.getSynthLogic(array.elements.single)!;
    expect(element, isA<SynthLogicArrayElement>());
    final firstConstant = Const(1, width: 8);
    final secondConstant = Const(2, width: 8);
    element.adopt(synth(firstConstant), force: true);
    final previous = element.logics;

    element.adopt(synth(secondConstant), force: true);

    expect(previous, isNot(contains(secondConstant)));
    expect(element.logics,
        containsAll([array.elements.single, firstConstant, secondConstant]));
    expect(element.logics, same(element.logics));
    expect(element.firstLogic, same(firstConstant));
  });

  for (final configuration in [
    (name: 'scalar', create: () => Logic(width: 8), isNet: false),
    (name: 'zero-width scalar', create: () => Logic(width: 0), isNet: false),
    (name: 'net', create: () => LogicNet(width: 8), isNet: true),
    (name: 'packed array', create: () => LogicArray([2], 4), isNet: false),
    (name: 'net array', create: () => LogicArray.net([2], 4), isNet: true),
    (
      name: 'unpacked array',
      create: () => LogicArray([2, 2], 2, numUnpackedDimensions: 1),
      isNet: false
    ),
  ]) {
    // Query metadata between merges, when a cached alias list would be stale.
    test('${configuration.name} metadata does not materialize aliases', () {
      final original = configuration.create();
      final signal = _CountingSynthLogic(original,
          parentSynthModuleDefinition: definition);
      for (var index = 0; index < 128; index++) {
        signal.adopt(synth(configuration.create()), force: true);
        expect(signal.width, original.width);
        expect(signal.isNet, configuration.isNet);
      }
      expect(signal.logicsReads, 0,
          reason: 'Metadata must not rebuild a growing alias snapshot.');
    });
  }
}
