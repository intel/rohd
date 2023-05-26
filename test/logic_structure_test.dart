// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// logic_structure_test.dart
// Tests for LogicStructure
//
// 2023 May 5
// Author: Max Korbel <max.korbel@intel.com>

import 'dart:io';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

//TODO: test port is a structure
//TODO: test port is a structure with an array in it
//TODO: test ports are components of a structure
//TODO: check coverage
//TODO: Test making a structure that extends LogicStructure
//TODO: test structures in conditional assignments
//TODO: test structures in If/Case expressions

class MyStruct extends LogicStructure {
  final Logic ready;
  final Logic valid;

  factory MyStruct() => MyStruct._(
        Logic(name: 'ready'),
        Logic(name: 'valid'),
      );

  MyStruct._(this.ready, this.valid) : super([ready, valid]);
}

class ModStructPort extends Module {
  ModStructPort(MyStruct struct) {
    final ready = addInput('ready', struct.ready);
    final valid = addOutput('valid');
    struct.valid <= valid;

    valid <= ready;
  }
}

void main() {
  group('LogicStructure construction', () {
    test('simple construction', () {
      final s = LogicStructure([
        Logic(),
        Logic(),
      ], name: 'structure');

      expect(s.name, 'structure');
    });
  });

  group('LogicStructures with modules', () {
    test('simple struct bi-directional', () async {
      final struct = MyStruct();
      final mod = ModStructPort(struct);
      await mod.build();
      print(mod.generateSynth()); //TODO
    });
  });
}
