// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// module_structure_test.dart
// Unit tests for the ModuleStructure model (empty / no-signal cases).
//
// 2026

import 'package:rohd_waveform/rohd_waveform.dart';
import 'package:test/test.dart';

void main() {
  group('ModuleStructure', () {
    test('empty has blank metadata and no modules', () {
      final structure = ModuleStructure.empty();
      expect(structure.modules, isEmpty);
      expect(structure.metadata, equals(MetaData.empty()));
      expect(structure.allSignalIds, isEmpty);
      expect(structure.firstModuleWithSignals, isNull);
    });

    test('value equality via Equatable', () {
      final a = ModuleStructure.empty();
      final b = ModuleStructure.empty();
      const c = ModuleStructure(
        metadata: MetaData(source: 'x', timescale: '1ns', date: 'd'),
        modules: [],
      );
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('withFirstRealModule returns the structure unchanged when empty', () {
      final structure = ModuleStructure.empty();
      expect(structure.withFirstRealModule(), same(structure));
    });
  });
}
