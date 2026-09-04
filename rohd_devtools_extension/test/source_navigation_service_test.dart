// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause

import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/flc_service.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/source_navigation_service.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart';

void main() {
  test('resolveSourceFrames falls back to original instance path for SV',
      () async {
    final flcService = FlcService(
      fetchModuleFlc: (definitionName) async {
        if (definitionName == 'floatingpoint_adder_singlepath') {
          return {
            'version': 6,
            'files': ['lib/src/floating_point.dart'],
            'modules': {
              'floatingpoint_adder_singlepath': {
                'outputFiles': {
                  'sv': ['FloatingPointAdderSinglePath.sv'],
                },
                'tree': [
                  ['0:10:5', 'lowerBitsPolarity@sv:20:3'],
                ],
              },
            },
          };
        }
        return {
          'version': 6,
          'files': ['lib/src/floating_point.dart'],
          'modules': {
            definitionName: {
              'outputFiles': {
                'sv': ['$definitionName.sv'],
              },
              'tree': [
                ['0:1:1', 'otherSignal@sv:2:1'],
              ],
            },
          },
        };
      },
      fetchFlcHierarchy: () async => null,
    );

    final nav = SourceNavigationService()
      ..setFlcService(flcService)
      ..setHierarchy(
        BaseHierarchyAdapter.fromTree(
          HierarchyOccurrence(
            name: 'top',
            children: [
              HierarchyOccurrence(
                name: 'floatingpoint_adder_singlepath',
                definition: 'FloatingPointAdderSinglePath_E4M4',
                signals: [
                  SignalOccurrence(name: 'lowerBitsPolarity', width: 1),
                ],
              ),
            ],
          ),
        ),
      );

    final frames = await nav.resolveSourceFrames(
      ['floatingpoint_adder_singlepath/lowerBitsPolarity'],
      format: RohdSourceFormat.sv,
    );

    expect(frames, hasLength(1));
    expect(frames.single.frame.file, 'FloatingPointAdderSinglePath.sv');
    expect(frames.single.frame.line, 20);
    expect(frames.single.frame.type, 'sv');
  });
}
