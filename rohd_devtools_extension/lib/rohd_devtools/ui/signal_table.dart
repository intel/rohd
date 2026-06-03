// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_table.dart
// UI for signal table field.
//
// 2024 January 5
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/signal_model.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/tree_model.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/services.dart';

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

  /// Creates a signal table for the given module and filters.
  const SignalTable({
    required this.selectedModule,
    required this.searchTerm,
    required this.inputSelectedVal,
    required this.outputSelectedVal,
    super.key,
  });

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
      ..add(FlagProperty('outputSelectedVal', value: outputSelectedVal));
  }
}

class _SignalTableState extends State<SignalTable> {
  @override

  /// Builds the signal table and its rows.
  Widget build(BuildContext context) {
    final tableHeaders = ['Name', 'Direction', 'Value', 'Width'];

    return Table(
      border: TableBorder.all(),
      columnWidths: const <int, TableColumnWidth>{
        0: FlexColumnWidth(),
        1: FlexColumnWidth(),
        2: FlexColumnWidth(),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: <TableRow>[
        TableRow(
          children: List<Widget>.generate(
            tableHeaders.length,
            (index) => _buildTableHeader(text: tableHeaders[index]),
          ),
        ),
        ...generateSignalsRow(
          widget.selectedModule,
          searchTerm: widget.searchTerm,
          inputSelected: widget.inputSelectedVal,
          outputSelected: widget.outputSelectedVal,
        ),
      ],
    );
  }

  /// Builds the rows for the signals that match the selected filters.
  List<TableRow> generateSignalsRow(
    TreeModel module, {
    required String? searchTerm,
    required bool inputSelected,
    required bool outputSelected,
  }) {
    final rows = <TableRow>[];

    // Filter signals
    final inputSignals = inputSelected
        ? SignalService.filterSignals(module.inputs, searchTerm ?? '')
        : <SignalModel>[];
    final outputSignals = outputSelected
        ? SignalService.filterSignals(module.outputs, searchTerm ?? '')
        : <SignalModel>[];
    // Add input from signal model list to row
    for (final signal in inputSignals) {
      rows.add(_generateSignalRow(signal));
    }

    // Add output from signal model list to row
    for (final signal in outputSignals) {
      rows.add(_generateSignalRow(signal));
    }

    return rows;
  }

  TableRow _generateSignalRow(SignalModel signal) => TableRow(
        children: <Widget>[
          SizedBox(
            height: 32,
            child: Center(child: Text(signal.name)),
          ),
          SizedBox(
            height: 32,
            child: Center(child: Text(signal.direction)),
          ),
          SizedBox(
            height: 32,
            child: Center(child: Text(signal.value)),
          ),
          SizedBox(
            height: 32,
            child: Center(child: Text(signal.width.toString())),
          ),
        ],
      );

  Widget _buildTableHeader({required String text}) => SizedBox(
        height: 32,
        child: Center(
          child: Text(
            text,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
        ),
      );
}
