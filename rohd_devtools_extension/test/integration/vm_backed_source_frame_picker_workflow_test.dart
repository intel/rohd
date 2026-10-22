// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// 2026 October 22
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/flc_service.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/io_vm_connection_strategy.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/source_navigation_service.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/vm_service_tree_data_source.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/source_frame_picker.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:vm_service/vm_service.dart';

import 'support/filter_bank_vm_target.dart';

class _VmSourceFrames {
  final FilterBankVmTarget target;
  final VmService vmService;
  final List<EnrichedFrame> frames;

  _VmSourceFrames({
    required this.target,
    required this.vmService,
    required this.frames,
  });

  Future<void> dispose() async {
    await vmService.dispose();
    await target.dispose();
  }
}

Future<_VmSourceFrames> _loadSourceFrames() async {
  final target = await startFilterBankVmTarget();
  try {
    final connection = await IoVmConnectionStrategy(
      retryDelay: const Duration(milliseconds: 50),
    ).connect(target.serviceUri);
    final treeSource = VmServiceTreeDataSource(
      vmService: connection.vmService,
      isolateId: connection.isolateId,
    );
    final root = await treeSource.evalModuleTree();
    if (root == null) {
      throw StateError('FilterBank hierarchy did not load from the VM target');
    }
    final hierarchy = await treeSource.fetchFlcHierarchy();
    final modules = hierarchy?['modules'];
    if (modules is! Map<String, dynamic> || modules.isEmpty) {
      throw StateError('FilterBank FLC hierarchy did not load from the VM');
    }
    final definition = modules.keys.first;
    final flcService = FlcService(
      fetchModuleFlc: treeSource.fetchModuleFlc,
      fetchFlcHierarchy: treeSource.fetchFlcHierarchy,
      fetchFlcFilePath: treeSource.fetchFlcFilePath,
      onClearCache: treeSource.clearFlcCache,
    );
    final sourceNavigation = SourceNavigationService()
      ..setFlcService(flcService)
      ..setHierarchy(BaseHierarchyAdapter.fromTree(root))
      ..sourceLineFetcher = treeSource.fetchSourceLine;

    final frames = <EnrichedFrame>[];
    for (final signal in root.depthFirstSignals()) {
      final resolved = await sourceNavigation.resolveSourceFrames([
        '$definition/${signal.name}',
      ]);
      frames.addAll(resolved);
      if (frames.length >= 2) {
        break;
      }
    }
    if (frames.length < 2) {
      throw StateError('FilterBank FLC data did not yield multiple frames');
    }

    return _VmSourceFrames(
      target: target,
      vmService: connection.vmService,
      frames: frames.take(2).toList(),
    );
  } on Object {
    await target.dispose();
    rethrow;
  }
}

void main() {
  testWidgets(
    'selects a real VM-backed source frame from the DevTools picker',
    (tester) async {
      final sourceFrames = await tester.runAsync(_loadSourceFrames);
      expect(sourceFrames, isNotNull);
      final vmFrames = sourceFrames!;
      addTearDown(vmFrames.dispose);
      tester.view
        ..physicalSize = const Size(1600, 1000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      int? selectedIndex;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => SourceFramePointerTracker(
                child: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      selectedIndex = await showSourceFramePicker(
                        context,
                        vmFrames.frames,
                        position: const Offset(300, 120),
                      );
                    },
                    child: const Text('Choose source frame'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Choose source frame'));
      await tester.pump();
      await tester.pumpAndSettle();
      final items = find.byType(PopupMenuItem<int>);
      expect(items, findsNWidgets(2));
      for (final frame in vmFrames.frames) {
        expect(find.text(frame.label), findsOneWidget);
      }

      await tester.tap(items.at(1));
      await tester.pump();
      await tester.pump();
      expect(selectedIndex, 1);
    },
    timeout: const Timeout(Duration(seconds: 180)),
  );
}
