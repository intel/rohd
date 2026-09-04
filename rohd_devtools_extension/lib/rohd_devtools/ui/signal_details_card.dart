// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_details_card.dart
// UI for signal details card.
//
// 2024 January 5
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cubit/cubits.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/tree_model.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/platform_icon.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/signal_table.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/signal_table_text_field.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart'
    show AvailableSourceFormats, GoToSourceCallback, RohdSourceFormat;

/// Card that displays signal details for a selected module.
class SignalDetailsCard extends StatefulWidget {
  /// The selected module whose signals are to be displayed.
  final TreeModel? module;

  /// Optional snapshot data to overlay signal values.
  final SnapshotLoaded? snapshot;

  /// Optional fallback for signals missing from the snapshot.
  final ({String value, bool computed})? Function(String signalPath)?
      _signalValueFallback;

  /// Called to eagerly expand a module's connectivity (slim → full JSON)
  /// so that the evaluator can compute internal signal values.
  ///
  /// Takes the module's instance path (e.g. `"top/adder0"`).
  final Future<void> Function(String moduleInstancePath)? _onExpandModule;

  /// Callback to send selected signal paths to waveform/schematic viewers.
  final void Function(List<String> signalPaths)? _onSendSignals;

  /// Callback to navigate to a signal's source for a chosen [RohdSourceFormat].
  final GoToSourceCallback? _onGoToSource;

  /// Discovers which source formats are navigable for the current module.
  final AvailableSourceFormats? _availableSourceFormats;

  /// Creates a [SignalDetailsCard] with the given selected module.
  const SignalDetailsCard({
    super.key,
    this.module,
    this.snapshot,
    ({String value, bool computed})? Function(String signalPath)?
        signalValueFallback,
    Future<void> Function(String moduleInstancePath)? onExpandModule,
    void Function(List<String> signalPaths)? onSendSignals,
    GoToSourceCallback? onGoToSource,
    AvailableSourceFormats? availableSourceFormats,
  })  : _signalValueFallback = signalValueFallback,
        _onExpandModule = onExpandModule,
        _onSendSignals = onSendSignals,
        _onGoToSource = onGoToSource,
        _availableSourceFormats = availableSourceFormats;

  @override
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
  /// The current search term for filtering signals.
  String? _searchTerm;

  @override
  void didUpdateWidget(covariant SignalDetailsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When the selected module changes and internals are already visible,
    // eagerly expand the new module's child definitions so the evaluator
    // has full connectivity data before signals are rendered.
    if (widget.module?.path() != oldWidget.module?.path() &&
        _internalsSelected.value) {
      unawaited(_expandModuleIfNeeded());
    }
  }

  /// Notifiers for input and output signal filters.
  final ValueNotifier<bool> _inputSelected = ValueNotifier<bool>(true);

  /// Notifiers for input and output signal filters.
  final ValueNotifier<bool> _outputSelected = ValueNotifier<bool>(true);

  /// Notifier for inout signal filter.
  final ValueNotifier<bool> _inoutSelected = ValueNotifier<bool>(true);

  /// Whether internal signals are shown.
  final ValueNotifier<bool> _internalsSelected = ValueNotifier<bool>(false);

  /// Notifier to trigger rebuilds.
  final ValueNotifier<int> _notifier = ValueNotifier<int>(0);

  /// Toggles the notifier to trigger a rebuild.
  void toggleNotifier() {
    _notifier.value++;
  }

  Future<void> _showFilterDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Filter Signals'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              CheckboxListTile(
                title: const Text('Input'),
                value: _inputSelected.value,
                onChanged: (value) {
                  setState(() {
                    _inputSelected.value = value!;
                  });
                  toggleNotifier();
                },
              ),
              CheckboxListTile(
                title: const Text('Output'),
                value: _outputSelected.value,
                onChanged: (value) {
                  setState(() {
                    _outputSelected.value = value!;
                  });
                  toggleNotifier();
                },
              ),
              CheckboxListTile(
                title: const Text('Inout'),
                value: _inoutSelected.value,
                onChanged: (value) {
                  setState(() {
                    _inoutSelected.value = value!;
                  });
                  toggleNotifier();
                },
              ),
              CheckboxListTile(
                title: const Text('Internal'),
                value: _internalsSelected.value,
                onChanged: (value) async {
                  setState(() {
                    _internalsSelected.value = value!;
                  });
                  if (value!) {
                    await _expandModuleIfNeeded();
                  }
                  toggleNotifier();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.module == null) {
      return const Padding(
        padding: EdgeInsets.only(top: 20),
        child: Center(child: Text('No module selected')),
      );
    }

    return SizedBox(
      height: MediaQuery.of(context).size.height / 1.4,
      child: SingleChildScrollView(
        child: Column(
          children: [
            // Snapshot header banner
            if (widget.snapshot != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                margin: const EdgeInsets.only(bottom: 4),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.camera_alt,
                      size: 16,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Snapshot @ ${widget.snapshot!.time}'
                      ' (${widget.snapshot!.signals.length} signals)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  SignalTableTextField(
                    labelText: 'Search Signals',
                    onChanged: (value) {
                      setState(() {
                        _searchTerm = value;
                      });
                      toggleNotifier();
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.filter_list),
                    onPressed: _showFilterDialog,
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: _internalsSelected,
                    builder: (context, active, _) => IconButton(
                      icon: platformIcon(
                        active ? Icons.visibility : Icons.visibility_off,
                        active ? '👁' : '🚫',
                        color: active ? null : Theme.of(context).disabledColor,
                      ),
                      tooltip: active
                          ? 'Hide internal signals'
                          : 'Show internal signals',
                      onPressed: () async {
                        final nowActive = !active;
                        _internalsSelected.value = nowActive;
                        if (nowActive) {
                          await _expandModuleIfNeeded();
                        }
                        toggleNotifier();
                      },
                    ),
                  ),
                ],
              ),
            ),
            ValueListenableBuilder(
              valueListenable: _notifier,
              builder: (context, _, __) => SignalTable(
                selectedModule: widget.module!,
                searchTerm: _searchTerm,
                inputSelectedVal: _inputSelected.value,
                outputSelectedVal: _outputSelected.value,
                inoutSelectedVal: _inoutSelected.value,
                internalsSelectedVal: _internalsSelected.value,
                snapshot: widget.snapshot,
                signalValueFallback: widget._signalValueFallback,
                onSendSignals: widget._onSendSignals,
                onGoToSource: widget._onGoToSource,
                availableSourceFormats: widget._availableSourceFormats,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Eagerly expand the selected module's connectivity when the
  /// internals toggle is activated.
  Future<void> _expandModuleIfNeeded() async {
    final modulePath = widget.module?.path();
    if (modulePath == null) {
      return;
    }
    await widget._onExpandModule?.call(modulePath);
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(StringProperty('searchTerm', _searchTerm))
      ..add(
        DiagnosticsProperty<ValueNotifier<bool>>(
          'inputSelected',
          _inputSelected,
        ),
      )
      ..add(
        DiagnosticsProperty<ValueNotifier<bool>>(
          'outputSelected',
          _outputSelected,
        ),
      )
      ..add(
        DiagnosticsProperty<ValueNotifier<bool>>(
          'inoutSelected',
          _inoutSelected,
        ),
      )
      ..add(DiagnosticsProperty<ValueNotifier<int>>('notifier', _notifier));
  }
}
