// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_table.dart
// UI for signal table field.
//
// 2024 January 5
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/models/signal_model.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/models/tree_model.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/providers/signal_service_provider.dart';

class SignalTable extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
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
          ref,
          selectedModule,
          searchTerm,
          inputSelectedVal,
          outputSelectedVal,
        ),
      ],
    );
  }

  List<TableRow> generateSignalsRow(
    WidgetRef ref,
    TreeModel module,
    String? searchTerm,
    bool inputSelected,
    bool outputSelected,
  ) {
    List<TableRow> rows = [];

    // Filter signals
    var inputSignals = inputSelected
        ? ref
            .read(signalServiceProvider)
            .filterSignals(module.inputs, searchTerm ?? '')
        : {};
    var outputSignals = outputSelected
        ? ref
            .read(signalServiceProvider)
            .filterSignals(module.outputs, searchTerm ?? '')
        : {};

    // Add Inputs
    for (var inputSignal in inputSignals.entries) {
      SignalModel signal = SignalModel.fromMap({
        'key': inputSignal.key,
        'direction': 'Input',
        'value': inputSignal.value['value'],
        'width': inputSignal.value['width'],
      });
      rows.add(_generateSignalRow(signal));
    }

    // Add Outputs
    for (var outputSignal in outputSignals.entries) {
      SignalModel signal = SignalModel.fromMap({
        'key': outputSignal.key,
        'direction': 'Output',
        'value': outputSignal.value['value'],
        'width': outputSignal.value['width'],
      });
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
