// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// module_structure_hierarchy_test.dart
// Tests waveform module structure root normalization.
//
// 2026 October
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_waveform/rohd_waveform.dart';
import 'package:test/test.dart';

void main() {
  group('resolveModuleStructure', () {
    test('preserves a single top-level module', () {
      final top = HierarchyOccurrence(
        name: 'top',
        signals: [SignalOccurrence(name: 'clock', width: 1)],
      );

      final resolved = resolveModuleStructure(
        ModuleStructure(metadata: MetaData.empty(), modules: [top]),
      );

      expect(resolved.root, same(top));
      expect(resolved.structure.modules, [same(top)]);
      expect(top.signals.single.address, isNotNull);
    });

    test('places sibling top-level modules under one addressed root', () {
      final alpha = HierarchyOccurrence(
        name: 'alpha',
        signals: [SignalOccurrence(name: 'a', width: 1)],
      );
      final beta = HierarchyOccurrence(
        name: 'beta',
        signals: [SignalOccurrence(name: 'b', width: 1)],
      );

      final resolved = resolveModuleStructure(
        ModuleStructure(metadata: MetaData.empty(), modules: [alpha, beta]),
      );

      expect(resolved.root.name, 'root');
      expect(resolved.root.children, [same(alpha), same(beta)]);
      expect(alpha.address, isNot(equals(beta.address)));
      expect(
        alpha.signals.single.address,
        isNot(equals(beta.signals.single.address)),
      );
      expect(
        resolved.hierarchyService.pathnameToAddress(
          alpha.signals.single.path(),
        ),
        alpha.signals.single.address,
      );
      expect(
        resolved.hierarchyService.pathnameToAddress(beta.signals.single.path()),
        beta.signals.single.address,
      );
    });

    test('rejects a waveform without module scopes', () {
      expect(
        () => resolveModuleStructure(
          ModuleStructure(metadata: MetaData.empty(), modules: const []),
        ),
        throwsStateError,
      );
    });
  });
}
