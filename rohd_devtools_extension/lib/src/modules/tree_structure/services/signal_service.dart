import 'package:flutter/material.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/models/signal_model.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/models/tree_model.dart';

class SignalService {
  Map<String, dynamic> filterSignals(
      Map<String, dynamic> signals, String searchTerm) {
    Map<String, dynamic> filtered = {};

    signals.forEach((key, value) {
      if (key.toLowerCase().contains(searchTerm.toLowerCase())) {
        filtered[key] = value;
      }
    });

    return filtered;
  }

  List<TableRow> generateSignalsRow(
    TreeModel module,
    String? searchTerm,
    bool inputSelected,
    bool outputSelected,
  ) {
    List<TableRow> rows = [];

    // Filter signals
    var inputSignals =
        inputSelected ? filterSignals(module.inputs, searchTerm ?? '') : {};
    var outputSignals =
        outputSelected ? filterSignals(module.outputs, searchTerm ?? '') : {};

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
            child: Text(signal.key),
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
            child: Text(signal.width),
          ),
        ),
      ],
    );
  }
}
