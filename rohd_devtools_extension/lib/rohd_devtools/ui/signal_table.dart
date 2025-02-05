// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_table.dart
// UI for signal table field.
//
// 2024 January 5
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cubit/rohd_service_cubit.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/signal_model.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/tree_model.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/signal_service.dart';

class SignalTable extends StatefulWidget {
  final TreeModel selectedModule;
  final String? searchTerm;
  final bool inputSelectedVal;
  final bool outputSelectedVal;
  const SignalTable({
    super.key,
    required this.selectedModule,
    required this.searchTerm,
    required this.inputSelectedVal,
    required this.outputSelectedVal,
  });

  @override
  State<StatefulWidget> createState() => _SignalTableState();
}

class _SignalTableState extends State<SignalTable> {
  @override
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
          widget.searchTerm,
          widget.inputSelectedVal,
          widget.outputSelectedVal,
        ),
      ],
    );
  }

  List<TableRow> generateSignalsRow(
    TreeModel module,
    String? searchTerm,
    bool inputSelected,
    bool outputSelected,
  ) {
    List<TableRow> rows = [];

    // Filter signals
    List<SignalModel> inputSignals = inputSelected
        ? SignalService.filterSignals(module.inputs, searchTerm ?? '')
        : [];
    List<SignalModel> outputSignals = outputSelected
        ? SignalService.filterSignals(module.outputs, searchTerm ?? '')
        : [];
    // Add input from signal model list to row
    for (var signal in inputSignals) {
      rows.add(_generateSignalRow(signal));
    }

    // Add output from signal model list to row
    for (var signal in outputSignals) {
      rows.add(_generateSignalRow(signal));
    }

    return rows;
  }

  TableRow _generateSignalRow(SignalModel signal) {
    return TableRow(
      children: <Widget>[
        SizedBox(
          height: 32,
          child: Center(
            child: Text(signal.name),
          ),
        ),
        SizedBox(
          height: 32,
          child: Center(
            child: Text(signal.direction),
          ),
        ),
        SizedBox(
          height: 32,
          child: Center(
            child: Text(signal.value),
          ),
        ),
        SizedBox(
          height: 32,
          child: Center(
            child: Text(signal.width.toString()),
          ),
        ),
      ],
    );
  }

  Widget _buildTableHeader({required String text}) {
    return SizedBox(
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
}
