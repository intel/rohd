// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// 2026 October 17
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:dtd/dtd.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/flc_service.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/source_navigation_service.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart';

class _MockDtd extends Mock implements DartToolingDaemon {}

void main() {
  test('returns local unavailable results without a resolver', () async {
    final nav = SourceNavigationService();
    const frame = EnrichedFrame(
      frame: SourceFrame(file: 'lib/src/demo.dart', line: 1, col: 1),
      label: 'demo.dart:1',
    );

    expect(nav.isAvailable, isFalse);
    expect(await nav.goToSourceFromPaths(['top/signal']), isFalse);
    expect(
      await nav.goToSourceFromSignals([
        {'module': 'top', 'name': 'signal'},
      ]),
      isFalse,
    );
    expect(await nav.resolveSourceFrames(['top/signal']), isEmpty);
    expect(await nav.navigateToFrame([frame], 0), isFalse);
    expect(
      await nav.navigateToFormat([frame], 0, RohdSourceFormat.rohd),
      isFalse,
    );
    nav
      ..clearDtd()
      ..clearHierarchy()
      ..clearSourceLineFetcher()
      ..clearFlcService();
  });

  test('decodes enriched-frame highlights in priority order', () {
    final decoded = EnrichedFrame.fromJson({
      'file': 'lib/src/demo.dart',
      'line': 7,
      'col': 3,
      'desc': 'signal',
      'type': 'rohd',
      'methodName': 'computeValue',
      'className': 'DemoModule',
      'label': 'demo.dart:7',
    });
    expect(decoded.frame.file, 'lib/src/demo.dart');
    expect(decoded.highlight, 'computeValue');
    expect(
      const EnrichedFrame(
        frame: SourceFrame(
          file: 'lib/src/demo.dart',
          line: 8,
          col: 1,
          desc: 'signal',
        ),
        label: 'demo.dart:8',
        className: 'DemoModule',
      ).highlight,
      'DemoModule',
    );
    expect(
      const EnrichedFrame(
        frame: SourceFrame(
          file: 'lib/src/demo.dart',
          line: 9,
          col: 1,
          desc: 'signal',
        ),
        label: 'demo.dart:9',
      ).highlight,
      'signal',
    );
    expect(
      const EnrichedFrame(
        frame: SourceFrame(file: 'lib/src/demo.dart', line: 10, col: 1),
        label: 'Demo.build()',
      ).highlight,
      'Demo',
    );
  });

  test(
    'resolveSourceFrames falls back to original instance path for SV',
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

      final frames = await nav.resolveSourceFrames([
        'floatingpoint_adder_singlepath/lowerBitsPolarity',
      ], format: RohdSourceFormat.sv);

      expect(frames, hasLength(1));
      expect(frames.single.frame.file, 'FloatingPointAdderSinglePath.sv');
      expect(frames.single.frame.line, 20);
      expect(frames.single.frame.type, 'sv');
    },
  );

  test(
    'uses local FLC resolution and reports unavailable editor navigation',
    () async {
      var moduleFetches = 0;
      final flcService = FlcService(
        fetchModuleFlc: (definitionName) async {
          moduleFetches++;
          if (definitionName != 'WidgetDef') {
            return null;
          }
          return {
            'version': 6,
            'files': ['lib/src/widget.dart'],
            'modules': {
              'WidgetDef': {
                'outputFiles': {
                  'sv': ['WidgetDef.sv'],
                },
                'tree': [
                  ['0:10:5', 'signal@sv:20:3'],
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
                  name: 'instance',
                  definition: 'WidgetDef',
                  signals: [
                    SignalOccurrence(name: 'signal', width: 1),
                  ],
                ),
              ],
            ),
          ),
        )
        ..sourceLineFetcher = (file, line) async =>
            file == 'WidgetDef.sv' && line == 20
                ? 'assign signal = inputValue;'
                : null;

      expect(nav.isAvailable, isTrue);
      final frames = await nav.resolveSourceFrames(
        ['top/instance/signal'],
        format: RohdSourceFormat.sv,
      );
      expect(frames, hasLength(1));
      expect(frames.single.frame.file, 'WidgetDef.sv');
      expect(frames.single.methodName, 'assign');
      expect(frames.single.highlight, 'assign');

      expect(
        await nav.goToSourceFromPaths(['top/instance/signal']),
        isFalse,
      );
      expect(
        await nav.goToSourceFromSignals([
          {'module': 'WidgetDef', 'name': 'signal'},
        ]),
        isFalse,
      );
      expect(
        await nav.navigateToFrame(frames, 0),
        isFalse,
      );
      expect(
        await nav.navigateToFormat(frames, 0, RohdSourceFormat.sv),
        isFalse,
      );
      expect(
        await nav.resolveSourceFrames(
          ['top/instance/missing'],
          format: RohdSourceFormat.sv,
        ),
        isEmpty,
      );
      final rohdFrames = await nav.resolveSourceFrames(
        ['top/instance/signal'],
        format: RohdSourceFormat.rohd,
      );
      expect(rohdFrames, hasLength(1));
      expect(rohdFrames.single.frame.type, 'rohd');
      expect(moduleFetches, 2);

      nav
        ..clearHierarchy()
        ..clearSourceLineFetcher()
        ..clearFlcService();
      expect(nav.isAvailable, isFalse);
      expect(
        await nav.resolveSourceFrames(
          ['top/instance/signal'],
          format: RohdSourceFormat.sv,
        ),
        isEmpty,
      );
    },
  );

  test(
    'uses an in-memory DTD transport for lookup and selected-frame navigation',
    () async {
      final dtd = _MockDtd();
      final calls =
          <({String? service, String method, Map<String, Object?>? params})>[];
      when(() => dtd.isClosed).thenReturn(false);
      when(
        () => dtd.call(any(), any(), params: any(named: 'params')),
      ).thenAnswer((invocation) async {
        final service = invocation.positionalArguments[0] as String?;
        final method = invocation.positionalArguments[1] as String;
        final params =
            invocation.namedArguments[#params] as Map<String, Object?>?;
        calls.add((service: service, method: method, params: params));
        if (method == 'lookupSignal') {
          return DTDResponse(
            'lookup',
            'response',
            {
              'status': 'ok',
              'frames': [
                {
                  'file': 'lib/src/inner.dart',
                  'line': 24,
                  'col': 3,
                  'desc': 'inner',
                  'type': 'rohd',
                },
                {
                  'file': 'lib/src/outer.dart',
                  'line': 9,
                  'col': 1,
                  'desc': 'outer',
                  'type': 'rohd',
                },
              ],
            },
          );
        }
        expect(method, 'goToSource');
        return DTDResponse(
          'navigate',
          'response',
          {'status': 'ok'},
        );
      });
      final flcService = FlcService(
        fetchModuleFlc: (_) async => null,
        fetchFlcHierarchy: () async => null,
        fetchFlcFilePath: () async => '/tmp/target.flc.json',
      );
      final nav = SourceNavigationService()
        ..setDtd(dtd)
        ..setFlcService(flcService)
        ..sourceLineFetcher = (file, line) async =>
            file == 'lib/src/outer.dart' && line == 9
                ? 'void outer() {}'
                : null;

      final frames = await nav.resolveSourceFrames(['top/Module/signal']);

      expect(frames.map((frame) => frame.frame.file), [
        'lib/src/outer.dart',
        'lib/src/inner.dart',
      ]);
      expect(frames.first.highlight, 'void outer');
      expect(
        await nav.navigateToFormat(frames, 1, RohdSourceFormat.rohd),
        isTrue,
      );
      expect(calls, hasLength(2));
      expect(calls.first.service, 'rohd');
      expect(calls.first.method, 'lookupSignal');
      expect(calls.first.params, hasLength(3));
      expect(calls.first.params, containsPair('signal', 'signal'));
      expect(calls.first.params, containsPair('module', 'Module'));
      expect(
        calls.first.params,
        containsPair('flcPath', '/tmp/target.flc.json'),
      );
      expect(calls.last.service, 'rohd');
      expect(calls.last.method, 'goToSource');
      expect(calls.last.params!['index'], 1);
      expect(calls.last.params!['highlight'], 'inner');
    },
  );

  test('falls back from an empty in-memory DTD lookup to local FLC data',
      () async {
    final dtd = _MockDtd();
    when(() => dtd.isClosed).thenReturn(false);
    when(
      () => dtd.call(any(), any(), params: any(named: 'params')),
    ).thenAnswer(
      (_) async => DTDResponse(
        'lookup',
        'response',
        {'status': 'not_found', 'frames': const []},
      ),
    );
    final flcService = FlcService(
      fetchModuleFlc: (definitionName) async => {
        'version': 6,
        'files': ['lib/src/module.dart'],
        'modules': {
          definitionName: {
            'outputFiles': {
              'sv': ['Module.sv'],
            },
            'tree': [
              ['0:10:5', 'signal@sv:20:3'],
            ],
          },
        },
      },
      fetchFlcHierarchy: () async => null,
      fetchFlcFilePath: () async => '/tmp/target.flc.json',
    );
    final nav = SourceNavigationService()
      ..setDtd(dtd)
      ..setFlcService(flcService);

    final frames = await nav.resolveSourceFrames(
      ['top/Module/signal'],
      format: RohdSourceFormat.sv,
    );

    expect(frames, hasLength(1));
    expect(frames.single.frame.file, 'Module.sv');
    expect(frames.single.frame.type, 'sv');
  });
}
