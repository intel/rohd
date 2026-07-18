// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_table.dart
// UI for signal table field.
//
// 2024 January 5
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cubit/snapshot_cubit.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/signal_model.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/tree_model.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/services.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/simulation_time_display.dart';

/// Displays the signals for a selected module in a table.
class SignalTable extends StatefulWidget {
  /// The module whose signals are shown in the table.
  final TreeModel selectedModule;

  /// Optional search term used to filter visible signals.
  final String? searchTerm;

  /// Whether input signals should be shown.
  final bool inputSelectedVal;

  /// Whether output signals should be shown.
  final bool outputSelectedVal;

  /// Whether inout signals should be shown.
  final bool inoutSelectedVal;

  /// Optional snapshot data to overlay signal values.
  final SnapshotLoaded? snapshot;

  /// Display settings for simulation time values.
  final SimulationTimeDisplay timeDisplay;

  /// Creates a signal table for the given module and filters.
  const SignalTable(
      {required this.selectedModule,
      required this.searchTerm,
      required this.inputSelectedVal,
      required this.outputSelectedVal,
      required this.inoutSelectedVal,
      this.snapshot,
      this.timeDisplay = SimulationTimeDisplay.none,
      super.key});

  @override

  /// Creates the state object for [SignalTable].
  State<SignalTable> createState() => _SignalTableState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<TreeModel>('selectedModule', selectedModule))
      ..add(StringProperty('searchTerm', searchTerm))
      ..add(FlagProperty('inputSelectedVal', value: inputSelectedVal))
      ..add(FlagProperty('outputSelectedVal', value: outputSelectedVal))
      ..add(FlagProperty('inoutSelectedVal', value: inoutSelectedVal))
      ..add(DiagnosticsProperty<SnapshotLoaded?>('snapshot', snapshot))
      ..add(DiagnosticsProperty<SimulationTimeDisplay>(
          'timeDisplay', timeDisplay));
  }
}

class _SignalTableState extends State<SignalTable> {
  @override

  /// Builds the signal table and its rows.
  Widget build(BuildContext context) {
    final snapshotTime = widget.snapshot?.time;
    final valueHeader = snapshotTime != null
        ? 'Value (@ ${widget.timeDisplay.format(snapshotTime)})'
        : 'Value';
    final tableHeaders = ['Name', 'Direction', valueHeader, 'Width'];

    return Table(
        border: TableBorder.all(),
        columnWidths: const <int, TableColumnWidth>{
          0: FlexColumnWidth(),
          1: FlexColumnWidth(),
          2: FlexColumnWidth()
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: <TableRow>[
          TableRow(
              children: List<Widget>.generate(tableHeaders.length,
                  (index) => _buildTableHeader(text: tableHeaders[index]))),
          ...generateSignalsRow(widget.selectedModule,
              searchTerm: widget.searchTerm,
              inputSelected: widget.inputSelectedVal,
              outputSelected: widget.outputSelectedVal,
              inoutSelected: widget.inoutSelectedVal)
        ]);
  }

  /// Builds the rows for the signals that match the selected filters.
  List<TableRow> generateSignalsRow(TreeModel module,
      {required String? searchTerm,
      required bool inputSelected,
      required bool outputSelected,
      required bool inoutSelected}) {
    final rows = <TableRow>[];

    // Filter signals
    final inputSignals = inputSelected
        ? SignalService.filterSignals(module.inputs, searchTerm ?? '')
        : <SignalModel>[];
    final outputSignals = outputSelected
        ? SignalService.filterSignals(module.outputs, searchTerm ?? '')
        : <SignalModel>[];
    final inoutSignals = inoutSelected
        ? SignalService.filterSignals(module.inouts, searchTerm ?? '')
        : <SignalModel>[];
    // Add input from signal model list to row
    for (final signal in inputSignals) {
      rows.add(_generateSignalRow(signal));
    }

    // Add output from signal model list to row
    for (final signal in outputSignals) {
      rows.add(_generateSignalRow(signal));
    }

    for (final signal in inoutSignals) {
      rows.add(_generateSignalRow(signal));
    }

    return rows;
  }

  TableRow _generateSignalRow(SignalModel signal) =>
      TableRow(children: <Widget>[
        SizedBox(height: 32, child: Center(child: Text(signal.name))),
        SizedBox(height: 32, child: Center(child: Text(signal.direction))),
        SizedBox(height: 32, child: Center(child: Text(_lookupValue(signal)))),
        SizedBox(
            height: 32, child: Center(child: Text(signal.width.toString())))
      ]);

  String _lookupValue(SignalModel signal) {
    // Snapshot overlay is currently keyed by signal name because the upstream
    // baseline does not yet thread a stable hierarchy-address identity through
    // the details table path. This keeps live values working now and leaves a
    // clear seam for the later hierarchy-address migration.
    final snapshotData = widget.snapshot;
    if (snapshotData != null) {
      final ss = snapshotData.getSignalByName(signal.name);
      if (ss != null) {
        return ss.value;
      }
    }
    return signal.value;
  }

  Widget _buildTableHeader({required String text}) => SizedBox(
      height: 32,
      child: Center(
          child: Text(text,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))));
}
