import 'package:flutter/material.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/models/tree_module.dart';

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
    for (var entry in inputSignals.entries) {
      rows.add(_generateSignalRow(
          entry.key, 'Input', entry.value as Map<String, dynamic>));
    }

    // Add Outputs
    for (var entry in outputSignals.entries) {
      rows.add(_generateSignalRow(
          entry.key, 'Output', entry.value as Map<String, dynamic>));
    }

    return rows;
  }

  TableRow _generateSignalRow(
      String key, String direction, Map<String, dynamic> value) {
    return TableRow(
      children: <Widget>[
        SizedBox(
          height: 32,
          child: Center(
            child: Text(key),
          ),
        ),
        SizedBox(
          height: 32,
          child: Center(
            child: Text(direction),
          ),
        ),
        SizedBox(
          height: 32,
          child: Center(
            child: Text('${value['value']}'),
          ),
        ),
        SizedBox(
          height: 32,
          child: Center(
            child: Text('${value['width']}'),
          ),
        ),
      ],
    );
  }
}
