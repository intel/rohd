// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// 2026 October 22
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

@TestOn('vm')
library;

import 'package:flutter/gestures.dart' show PointerDeviceKind, kSecondaryButton;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cubit/cubits.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/io_vm_connection_strategy.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/vm_service_signal_waveform_api.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/vm_service_transport.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/vm_service_tree_data_source.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/waveform_signal_value_source.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/details_panel_content.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/module_search_overlay.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/module_tree_card.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/module_tree_details_navbar.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/signal_details_card.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/signal_table.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart'
    show RohdSourceFormat;
import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_waveform/rohd_waveform.dart' as waveform;
import 'package:vm_service/vm_service.dart';

import 'support/filter_bank_vm_target.dart';

class _VmBackedUiData {
  final FilterBankVmTarget target;
  final VmService vmService;
  final VmServiceTransport transport;
  final VmServiceSignalWaveformApi waveformApi;
  final HierarchyOccurrence root;
  final int currentTime;

  _VmBackedUiData({
    required this.target,
    required this.vmService,
    required this.transport,
    required this.waveformApi,
    required this.root,
    required this.currentTime,
  });

  Future<void> dispose() async {
    await transport.dispose();
    await vmService.dispose();
    await target.dispose();
  }
}

Future<int> _waitForWaveformTime(VmServiceTransport transport) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    final time = await transport.getCurrentTime();
    if (time != null && time > 0) {
      return time;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError('FilterBank VM target did not record waveform data');
}

Future<_VmBackedUiData> _loadVmBackedUiData() async {
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
    final schematic = treeSource.getSchematicJson();
    final modules = schematic?['modules'];
    if (modules is! Map<String, dynamic>) {
      throw StateError('FilterBank VM target did not return a schematic');
    }

    final transport = VmServiceTransport(
      vmService: connection.vmService,
      isolateId: connection.isolateId,
    );
    final currentTime = await _waitForWaveformTime(transport);
    final waveformApi = VmServiceSignalWaveformApi(transport)
      ..schematicModules = modules
      ..fetchModuleSchematic = treeSource.fetchModuleSchematic;
    await waveformApi.setExternalStructure(
      waveform.ModuleStructure(
        metadata: waveform.MetaData.empty(),
        modules: [root],
      ),
    );

    return _VmBackedUiData(
      target: target,
      vmService: connection.vmService,
      transport: transport,
      waveformApi: waveformApi,
      root: root,
      currentTime: currentTime,
    );
  } on Object {
    await target.dispose();
    rethrow;
  }
}

void main() {
  testWidgets(
    'drives DevTools hierarchy, details, and tab interactions from a real VM',
    (tester) async {
      final data = await tester.runAsync(_loadVmBackedUiData);
      expect(data, isNotNull);
      final vmData = data!;
      addTearDown(vmData.dispose);
      final searchableModule = vmData.root.children.firstWhere(
        (module) => !module.isPrimitiveCell,
      );

      final hierarchyCubit = DevToolsHierarchyCubit()
        ..loadFromNode(vmData.root);
      final detailsTabCubit = DetailsTabCubit();
      final snapshotCubit = SnapshotCubit();
      final treeSearchCubit = TreeSearchTermCubit();
      final themeCubit = DevToolsThemeCubit();
      addTearDown(hierarchyCubit.close);
      addTearDown(detailsTabCubit.close);
      addTearDown(snapshotCubit.close);
      addTearDown(treeSearchCubit.close);
      addTearDown(themeCubit.close);

      await tester.runAsync(
        () => snapshotCubit.takeSnapshot(
          WaveformSignalValueSource(api: vmData.waveformApi),
          vmData.currentTime,
        ),
      );
      expect(snapshotCubit.state, isA<SnapshotLoaded>());

      var expansionRequests = 0;
      final sentSignalBatches = <List<String>>[];
      final sourceRequests =
          <({RohdSourceFormat format, List<String> paths})>[];
      tester.view
        ..physicalSize = const Size(1440, 1000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider.value(value: hierarchyCubit),
            BlocProvider.value(value: detailsTabCubit),
            BlocProvider.value(value: snapshotCubit),
            BlocProvider.value(value: treeSearchCubit),
            BlocProvider.value(value: themeCubit),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Row(
                children: [
                  SizedBox(
                    width: 420,
                    child: Column(
                      children: [
                        ModuleSearchField(
                          hierarchy: hierarchyCubit.currentService,
                          onSearchTermChanged: treeSearchCubit.setTerm,
                        ),
                        Expanded(
                          child: ModuleTreeCard(
                            futureModuleTree: vmData.root,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: DetailsPanelContent(
                      waveformConfig: const WaveformTabConfig(
                        waveformViewer: Center(
                          child: Text('DevTools waveform host'),
                        ),
                      ),
                      schematicConfig: SchematicTabConfig(
                        assetPath: 'unused.json',
                        customWidgetBuilder: ({required isVisible}) => Center(
                          child: Text(
                            isVisible
                                ? 'DevTools schematic host active'
                                : 'DevTools schematic host inactive',
                          ),
                        ),
                      ),
                      onExpandModule: (modulePath) async {
                        expansionRequests++;
                        await vmData.waveformApi.ensureFullModules(
                          '$modulePath/_details',
                        );
                      },
                      onSendSignals: sentSignalBatches.add,
                      onGoToSource: (format, paths) {
                        sourceRequests.add((format: format, paths: paths));
                      },
                      availableSourceFormats: () => const [
                        RohdSourceFormat.rohd,
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final moduleSearch = find.byType(ModuleSearchField);
      final moduleSearchInput = find.descendant(
        of: moduleSearch,
        matching: find.byType(TextField),
      );
      expect(moduleSearchInput, findsOneWidget);
      await tester.enterText(moduleSearchInput, searchableModule.name);
      await tester.pump();
      final searchResults = find.descendant(
        of: moduleSearch,
        matching: find.byType(InkWell),
      );
      expect(searchResults, findsWidgets);
      await tester.tap(searchResults.first);
      await tester.pump();
      expect(hierarchyCubit.selectedModule?.path(), searchableModule.path());
      expect(find.byType(SignalDetailsCard), findsOneWidget);
      expect(find.textContaining('Snapshot @'), findsOneWidget);

      final signalFilter = find.descendant(
        of: find.byType(SignalDetailsCard),
        matching: find.byType(TextField),
      );
      expect(signalFilter, findsOneWidget);
      await tester.enterText(signalFilter, 'clk');
      await tester.pump();
      expect(find.text('clk'), findsWidgets);
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump();

      final signalTable = find.byType(SignalTable);
      expect(signalTable, findsOneWidget);
      expect(searchableModule.inputs, isNotEmpty);
      expect(searchableModule.outputs, isNotEmpty);
      final inputSignal = searchableModule.inputs.first;
      final outputSignal = searchableModule.outputs.first;

      await tester.tap(
        find.ancestor(
          of: find.byIcon(Icons.filter_list),
          matching: find.byType(IconButton),
        ),
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Input'));
      await tester.pump();
      await tester.tapAt(const Offset(10, 990));
      await tester.pump();
      expect(find.text(inputSignal.name), findsNothing);
      expect(find.text(outputSignal.name), findsWidgets);

      await tester.tap(
        find.ancestor(
          of: find.byIcon(Icons.filter_list),
          matching: find.byType(IconButton),
        ),
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Input'));
      await tester.pump();
      await tester.tapAt(const Offset(10, 990));
      await tester.pump();
      expect(find.text(inputSignal.name), findsWidgets);

      final nameHeader = find.descendant(
        of: signalTable,
        matching: find.text('Name'),
      );
      await tester.tap(nameHeader);
      await tester.pump();
      expect(
        find.descendant(
            of: signalTable, matching: find.byIcon(Icons.arrow_upward)),
        findsOneWidget,
      );
      await tester.tap(nameHeader);
      await tester.pump();
      expect(
        find.descendant(
          of: signalTable,
          matching: find.byIcon(Icons.arrow_downward),
        ),
        findsOneWidget,
      );
      await tester.tap(nameHeader);
      await tester.pump();
      expect(
        find.descendant(
          of: signalTable,
          matching: find.byIcon(Icons.arrow_upward),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: signalTable,
          matching: find.byIcon(Icons.arrow_downward),
        ),
        findsNothing,
      );

      final valueHeader = find.descendant(
        of: signalTable,
        matching: find.text('Value (@ ${vmData.currentTime})'),
      );
      for (var index = 0; index < 3; index++) {
        await tester.tap(valueHeader);
        await tester.pump();
      }
      expect(
        find.descendant(
          of: signalTable,
          matching: find.byIcon(Icons.arrow_upward),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: signalTable,
          matching: find.byIcon(Icons.arrow_downward),
        ),
        findsNothing,
      );

      final tableSignals = [
        ...searchableModule.inputs,
        ...searchableModule.outputs,
        ...searchableModule.inouts,
      ];
      expect(tableSignals.length, greaterThanOrEqualTo(2));
      final firstSignal = tableSignals[0];
      final secondSignal = tableSignals[1];
      final firstSignalText = find.descendant(
        of: signalTable,
        matching: find.text(firstSignal.name),
      );
      final secondSignalText = find.descendant(
        of: signalTable,
        matching: find.text(secondSignal.name),
      );
      await tester.tap(firstSignalText);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(secondSignalText);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      Future<void> openContextMenu(Finder finder) async {
        await tester.ensureVisible(finder);
        final contextMenuGesture = await tester.startGesture(
          tester.getCenter(finder),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryButton,
        );
        await contextMenuGesture.up();
        await tester.pump();
        await tester.pumpAndSettle();
      }

      await openContextMenu(firstSignalText);
      expect(find.text('Go to ROHD Source (2)'), findsOneWidget);
      await tester.tap(find.text('Go to ROHD Source (2)'));
      await tester.pumpAndSettle();
      expect(sourceRequests, hasLength(1));
      expect(sourceRequests.single.format, RohdSourceFormat.rohd);
      expect(
        sourceRequests.single.paths,
        [firstSignal.path(), secondSignal.path()],
      );

      await openContextMenu(firstSignalText);
      expect(find.text('Send 2 Signals'), findsOneWidget);
      await tester.tap(find.text('Send 2 Signals'));
      await tester.pump();
      expect(sentSignalBatches, hasLength(1));
      expect(
        sentSignalBatches.single,
        [firstSignal.path(), secondSignal.path()],
      );

      final wideSignal = tableSignals.firstWhere((signal) => signal.width > 1);
      final wideSignalText = find.descendant(
        of: signalTable,
        matching: find.text(wideSignal.name),
      );
      await tester.tap(wideSignalText);
      await tester.pump();
      await openContextMenu(wideSignalText);
      final expandBitsAction = find.text('Expand Bits [${wideSignal.width}]');
      expect(expandBitsAction, findsOneWidget);
      await tester.tap(expandBitsAction);
      await tester.pumpAndSettle();

      final bitRangeDialog = find.byType(AlertDialog);
      expect(bitRangeDialog, findsOneWidget);
      final bitRangeInput = find.descendant(
        of: bitRangeDialog,
        matching: find.byType(TextField),
      );
      await tester.enterText(bitRangeInput, '1:0');
      await tester.tap(
        find.descendant(of: bitRangeDialog, matching: find.text('OK')),
      );
      await tester.pumpAndSettle();
      expect(
        sentSignalBatches,
        [
          [firstSignal.path(), secondSignal.path()],
          ['${wideSignal.path()}#b[0]', '${wideSignal.path()}#b[1]'],
        ],
      );

      await tester.ensureVisible(find.text('Bits'));
      await tester.tap(find.text('Bits'));
      await tester.pump();
      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);

      await tester.tap(
        find.ancestor(
          of: find.byIcon(Icons.filter_list),
          matching: find.byType(IconButton),
        ),
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Internal'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      expect(expansionRequests, 1);
      await tester.tapAt(const Offset(10, 990));
      await tester.pump();
      expect(find.text('Filter Signals'), findsNothing);

      final tabs = find.byType(ModuleTreeDetailsNavbar);
      expect(tabs, findsOneWidget);
      await tester
          .tap(find.descendant(of: tabs, matching: find.text('Waveform')));
      await tester.pump();
      expect(detailsTabCubit.state, DetailsTab.waveform);

      await tester
          .tap(find.descendant(of: tabs, matching: find.text('Schematic')));
      await tester.pump();
      expect(detailsTabCubit.state, DetailsTab.schematic);
      expect(find.text('DevTools schematic host active'), findsOneWidget);

      await tester
          .tap(find.descendant(of: tabs, matching: find.text('Details')));
      await tester.pump();
      expect(detailsTabCubit.state, DetailsTab.details);
    },
    timeout: const Timeout(Duration(seconds: 180)),
  );
}
