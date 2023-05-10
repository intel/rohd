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
}
