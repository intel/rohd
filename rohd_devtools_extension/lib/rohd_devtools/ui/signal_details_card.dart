// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_details_card.dart
// UI for signal details card.
//
// 2024 January 5
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cubit/snapshot_cubit.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/tree_model.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/details_help_button.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/signal_table.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/signal_table_text_field.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart';

/// Shows the selected module's signal details and search controls.
class SignalDetailsCard extends StatefulWidget {
  /// The module currently selected for inspection.
  final TreeModel? module;

  /// Optional snapshot data to overlay signal values.
  final SnapshotLoaded? snapshot;

  /// Creates a signal details card for the selected module.
  const SignalDetailsCard({super.key, this.module, this.snapshot});

  @override

  /// Creates the mutable state for [SignalDetailsCard].
  SignalDetailsCardState createState() => SignalDetailsCardState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<TreeModel?>('module', module))
      ..add(DiagnosticsProperty<SnapshotLoaded?>('snapshot', snapshot));
  }
}

/// State for [SignalDetailsCard].
class SignalDetailsCardState extends State<SignalDetailsCard> {
  /// Search term used to filter signals.
  String? searchTerm;

  /// Whether input signals are shown.
  ValueNotifier<bool> inputSelected = ValueNotifier<bool>(true);

  /// Whether output signals are shown.
  ValueNotifier<bool> outputSelected = ValueNotifier<bool>(true);

  /// Notifies the widget tree to rebuild after filter changes.
  ValueNotifier<int> notifier = ValueNotifier<int>(0);

  /// Boundary used when exporting the signal details panel as PNG.
  final GlobalKey _boundaryKey = GlobalKey();

  /// Increments the rebuild notifier.
  void toggleNotifier() => notifier.value++;

  void _showFilterDialog() {
    unawaited(showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, setState) => AlertDialog(
                title: const Text('Filter Signals'),
                content:
                    Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                  CheckboxListTile(
                      title: const Text('Input'),
                      value: inputSelected.value,
                      onChanged: (value) {
                        setState(() {
                          inputSelected.value = value!;
                        });
                        toggleNotifier();
                      }),
                  CheckboxListTile(
                      title: const Text('Output'),
                      value: outputSelected.value,
                      onChanged: (value) {
                        setState(() {
                          outputSelected.value = value!;
                        });
                        toggleNotifier();
                      })
                ])))));
  }

  @override

  /// Builds the signal details panel for the selected module.
  Widget build(BuildContext context) {
    if (widget.module == null) {
      return const Padding(
          padding: EdgeInsets.only(top: 20),
          child: Center(child: Text('No module selected')));
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(fit: StackFit.expand, children: [
      RepaintBoundary(
          key: _boundaryKey,
          child: SingleChildScrollView(
              child: Column(children: [
            Padding(
                padding: const EdgeInsets.all(8),
                child: Row(children: [
                  SignalTableTextField(
                      labelText: 'Search Signals',
                      onChanged: (value) {
                        setState(() {
                          searchTerm = value;
                        });
                        toggleNotifier();
                      }),
                  IconButton(
                      icon: const Icon(Icons.filter_list),
                      onPressed: _showFilterDialog),
                  DetailsHelpButton(isDark: isDark)
                ])),
            ValueListenableBuilder(
                valueListenable: notifier,
                builder: (context, _, __) => SignalTable(
                    selectedModule: widget.module!,
                    searchTerm: searchTerm,
                    inputSelectedVal: inputSelected.value,
                    outputSelectedVal: outputSelected.value,
                    snapshot: widget.snapshot))
          ]))),
      Positioned(
          right: 8,
          bottom: 8,
          child: ExportPngButton(
              onPressed: () => captureBoundaryToPng(context,
                  boundaryKey: _boundaryKey, filePrefix: 'signal_details')))
    ]);
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(StringProperty('searchTerm', searchTerm))
      ..add(FlagProperty('inputSelected', value: inputSelected.value))
      ..add(FlagProperty('outputSelected', value: outputSelected.value))
      ..add(IntProperty('notifier', notifier.value));
  }
}
