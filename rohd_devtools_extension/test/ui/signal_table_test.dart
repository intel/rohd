// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_table_test.dart
// Tests for signal table filtering and value display.
//
// 2026 July
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cubit/snapshot_cubit.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/signal_model.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/tree_model.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/signal_table.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/simulation_time_display.dart';

final _module = TreeModel(
  name: 'counter',
  inputs: [
    SignalModel(
      name: 'clock',
      direction: 'Input',
      value: "1'h0",
      width: 1,
    ),
  ],
  outputs: [
    SignalModel(
      name: 'count',
      direction: 'Output',
      value: "8'h00",
      width: 8,
    ),
  ],
  inouts: [
    SignalModel(
      name: 'bus',
      direction: 'Inout',
      value: "4'hf",
      width: 4,
    ),
  ],
  subModules: const [],
);

Widget _buildTable({
  String? searchTerm,
  bool inputSelected = true,
  bool outputSelected = true,
  bool inoutSelected = true,
  SnapshotLoaded? snapshot,
  SimulationTimeDisplay timeDisplay = SimulationTimeDisplay.none,
}) =>
    MaterialApp(
      home: Scaffold(
        body: SignalTable(
          selectedModule: _module,
          searchTerm: searchTerm,
          inputSelectedVal: inputSelected,
          outputSelectedVal: outputSelected,
          inoutSelectedVal: inoutSelected,
          snapshot: snapshot,
          timeDisplay: timeDisplay,
        ),
      ),
    );

void main() {
  testWidgets('renders every signal and overlays available snapshot values',
      (tester) async {
    const snapshot = SnapshotLoaded(
      time: 17,
      signals: {
        'counter.count': SignalSnapshot(
          signalId: 'counter.count',
          name: 'count',
          value: "8'h2a",
          width: 8,
        ),
      },
    );

    await tester.pumpWidget(
      _buildTable(
        snapshot: snapshot,
        timeDisplay: const SimulationTimeDisplay(unit: 'ns'),
      ),
    );

    expect(find.text('Value (@ 17ns)'), findsOneWidget);
    expect(find.text('clock'), findsOneWidget);
    expect(find.text('count'), findsOneWidget);
    expect(find.text('bus'), findsOneWidget);
    expect(find.text("8'h2a"), findsOneWidget);
    expect(find.text("8'h00"), findsNothing);
  });

  testWidgets('applies search and direction filters before rendering rows',
      (tester) async {
    await tester.pumpWidget(
      _buildTable(
        searchTerm: 'bus',
        inputSelected: false,
        outputSelected: false,
      ),
    );

    expect(find.text('bus'), findsOneWidget);
    expect(find.text('clock'), findsNothing);
    expect(find.text('count'), findsNothing);
    expect(find.text('Inout'), findsOneWidget);
  });
}
