// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_table.dart
// UI for signal table field.
//
// 2024 January 5
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd/rohd.dart' hide State;
import 'package:rohd_devtools_extension/rohd_devtools/cubit/cubits.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/signal_model.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/tree_model.dart';
import 'package:rohd_devtools_extension/rohd_devtools/utils/regex_utils.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart'
    show
        AvailableSourceFormats,
        BitDefineFieldsAction,
        BitExpandRangeAction,
        BitFieldUtils,
        GoToSourceCallback,
        RohdSourceFormat,
        SignalValueFormatRegistry,
        TypeFieldNode,
        buildBitExpansionMenuItems,
        buildGotoSourceMenuItems,
        expandLogicType,
        formatFieldValue,
        gotoSourceFormatFromValue,
        hexToBinary,
        kDefaultNavigableFormats,
        resolveBitExpansionMenuValue;
import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_wave_viewer/rohd_wave_viewer.dart'
    show showSignalFormatMenu, signalFormatMenuValue;
import 'package:rohd_waveform/rohd_waveform.dart' show MonitorValueFormat;

/// Widget that displays a table of signals for a selected module.
class SignalTable extends StatefulWidget {
  /// The selected module whose signals are to be displayed.
  final TreeModel selectedModule;

  /// The search term for filtering signals.
  final String? searchTerm;

  /// Whether input signals are selected for display.
  final bool inputSelectedVal;

  /// Whether output signals are selected for display.
  final bool outputSelectedVal;

  /// Whether inout signals are selected for display.
  final bool inoutSelectedVal;

  /// Whether internal signals are selected for display.
  final bool internalsSelectedVal;

  /// Optional snapshot data to overlay signal values.
  final SnapshotLoaded? snapshot;

  /// Optional fallback for signals missing from the snapshot.
  ///
  /// Called with the signal's [SignalOccurrence.path].  Returns a value/computed
  /// pair when the client-side evaluator can derive the value, or `null`.
  final ({String value, bool computed})? Function(String signalPath)?
      signalValueFallback;

  /// Callback to send selected signal paths to waveform/schematic viewers.
  final void Function(List<String> signalPaths)? onSendSignals;

  /// Callback to navigate to a signal's source for a chosen [RohdSourceFormat].
  final GoToSourceCallback? onGoToSource;

  /// Discovers which source formats are navigable for the current module.
  final AvailableSourceFormats? availableSourceFormats;

  /// Creates a [SignalTable] with the given parameters.
  const SignalTable({
    required this.selectedModule,
    required this.searchTerm,
    required this.inputSelectedVal,
    required this.outputSelectedVal,
    required this.inoutSelectedVal,
    this.internalsSelectedVal = false,
    this.snapshot,
    this.signalValueFallback,
    this.onSendSignals,
    this.onGoToSource,
    this.availableSourceFormats,
    super.key,
  });

  @override
  State<StatefulWidget> createState() => _SignalTableState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<TreeModel>('selectedModule', selectedModule))
      ..add(StringProperty('searchTerm', searchTerm))
      ..add(DiagnosticsProperty<bool>('inputSelectedVal', inputSelectedVal))
      ..add(DiagnosticsProperty<bool>('outputSelectedVal', outputSelectedVal))
      ..add(DiagnosticsProperty<bool>('inoutSelectedVal', inoutSelectedVal))
      ..add(
        DiagnosticsProperty<bool>('internalsSelectedVal', internalsSelectedVal),
      )
      ..add(DiagnosticsProperty<SnapshotLoaded?>('snapshot', snapshot))
      ..add(
        ObjectFlagProperty<
                ({bool computed, String value})? Function(
                    String signalPath)?>.has(
            'signalValueFallback', signalValueFallback),
      )
      ..add(
        ObjectFlagProperty<void Function(List<String> signalPaths)?>.has(
          'onSendSignals',
          onSendSignals,
        ),
      )
      ..add(
        ObjectFlagProperty<GoToSourceCallback?>.has(
          'onGoToSource',
          onGoToSource,
        ),
      )
      ..add(
        ObjectFlagProperty<AvailableSourceFormats?>.has(
          'availableSourceFormats',
          availableSourceFormats,
        ),
      );
  }
}

class _SignalTableState extends State<SignalTable> {
  /// Current sort column index (null = unsorted).
  int? _sortColumnIndex;

  /// True = ascending, false = descending.
  bool _sortAscending = true;

  /// Indices of selected rows (for multi-select).
  final Set<int> _selectedIndices = {};

  /// Signal paths that are currently expanded to show sub-fields.
  final Set<String> _expandedSignals = {};

  /// Sub-field paths expanded within the type tree (e.g.
  /// "top.mod.sig/field" or "top.mod.sig/[0]").
  /// Only one hierarchy level is shown per expansion.
  final Set<String> _expandedSubFields = {};

  /// Index of the last single-clicked row (anchor for Shift-click ranges).
  int? _lastClickedIndex;

  /// Key of the currently selected sub-field row (null = none).
  ///
  /// Sub-fields are not part of the flat row index space, so they use their
  /// hierarchical key (e.g. `top.mod.sig/field/sub`) as the selection identity
  /// instead of an integer index.
  String? _selectedSubFieldKey;

  @override
  void initState() {
    super.initState();
    SignalValueFormatRegistry.changes.addListener(_onFormatChange);
  }

  @override
  void dispose() {
    SignalValueFormatRegistry.changes.removeListener(_onFormatChange);
    super.dispose();
  }

  void _onFormatChange() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(covariant SignalTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedModule != oldWidget.selectedModule ||
        widget.searchTerm != oldWidget.searchTerm ||
        widget.inputSelectedVal != oldWidget.inputSelectedVal ||
        widget.outputSelectedVal != oldWidget.outputSelectedVal ||
        widget.internalsSelectedVal != oldWidget.internalsSelectedVal) {
      _selectedIndices.clear();
      _lastClickedIndex = null;
      _selectedSubFieldKey = null;
    }
  }

  void _onRowTap(int index) {
    setState(() {
      _selectedSubFieldKey = null;
      final keys = HardwareKeyboard.instance.logicalKeysPressed;
      final isShift = keys.contains(LogicalKeyboardKey.shiftLeft) ||
          keys.contains(LogicalKeyboardKey.shiftRight);
      final isCtrl = keys.contains(LogicalKeyboardKey.controlLeft) ||
          keys.contains(LogicalKeyboardKey.controlRight) ||
          keys.contains(LogicalKeyboardKey.metaLeft) ||
          keys.contains(LogicalKeyboardKey.metaRight);

      if (isShift && _lastClickedIndex != null) {
        final lo = _lastClickedIndex! < index ? _lastClickedIndex! : index;
        final hi = _lastClickedIndex! < index ? index : _lastClickedIndex!;
        for (var i = lo; i <= hi; i++) {
          _selectedIndices.add(i);
        }
      } else if (isCtrl) {
        if (_selectedIndices.contains(index)) {
          _selectedIndices.remove(index);
        } else {
          _selectedIndices.add(index);
        }
      } else {
        _selectedIndices
          ..clear()
          ..add(index);
      }
      _lastClickedIndex = index;
    });
  }

  /// Filter signals by name, fullPath, or path().
  ///
  /// Supports regex patterns (auto-detected by metacharacter presence).
  /// Plain text uses case-insensitive prefix matching on name and
  /// path(); regex uses `hasMatch` across all three fields.
  static List<SignalModel> _filterSignals(
    List<SignalModel> signals,
    String searchTerm,
  ) {
    if (searchTerm.isEmpty) {
      return signals;
    }

    final hasRegexMeta = regExpHasMatch(r'[.*+?^${}()|[\]\\]', searchTerm);

    if (hasRegexMeta) {
      try {
        final re = regExpPattern(searchTerm, caseSensitive: false);
        return signals
            .where(
              (s) =>
                  s.name.contains(re) ||
                  s.path().contains(re) ||
                  s.path().contains(re),
            )
            .toList();
      } on FormatException catch (_) {
        // Invalid regex — fall back to plain prefix match.
        final lower = searchTerm.toLowerCase();
        return signals
            .where(
              (s) =>
                  s.name.toLowerCase().startsWith(lower) ||
                  s.path().toLowerCase().startsWith(lower),
            )
            .toList();
      }
    } else {
      // Plain text: case-insensitive prefix match.
      final lower = searchTerm.toLowerCase();
      return signals
          .where(
            (s) =>
                s.name.toLowerCase().startsWith(lower) ||
                s.path().toLowerCase().startsWith(lower),
          )
          .toList();
    }
  }

  /// Format a signal value for display using ROHD's radixString format.
  ///
  /// Values arriving from the VM or evaluators are already in radixString
  /// format (`<width>'h<hex>`).  This method normalises legacy `0x`/binary
  /// formats and passes well-formed radixStrings through.
  String _formatValue(String? value, {int? width}) {
    if (value == null) {
      return '';
    }

    final v = value.trim().replaceAll('\u0000', '');
    if (v.isEmpty) {
      return v;
    }

    // Already a radixString (e.g. 16'hfffe, 8'bxxxx0101) — pass through.
    if (regExpHasMatch(r"^\d+'[bqodh]", v)) {
      return v;
    }

    // Legacy 0x / 0b / bare value — convert via LogicValue.
    final w = (width != null && width > 0) ? width : 1;
    try {
      final lower = v.toLowerCase();
      BigInt? parsed;
      if (lower.startsWith('0x')) {
        parsed = BigInt.tryParse(lower.substring(2), radix: 16);
      } else if (lower.startsWith('0b')) {
        parsed = BigInt.tryParse(lower.substring(2), radix: 2);
      } else {
        parsed = BigInt.tryParse(lower);
      }
      if (parsed != null) {
        return LogicValue.ofBigInt(parsed, w).toString();
      }
      return v;
    } on Object {
      return v;
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshotTime = widget.snapshot?.time;
    final valueHeader =
        snapshotTime != null ? 'Value (@ $snapshotTime)' : 'Value';
    final tableHeaders = ['Name', 'Bits', 'Direction', valueHeader];

    // Collect all signals matching the current filters.
    final allRows = _collectSignals(
      widget.selectedModule,
      inputSelected: widget.inputSelectedVal,
      outputSelected: widget.outputSelectedVal,
      inoutSelected: widget.inoutSelectedVal,
      internalsSelected: widget.internalsSelectedVal,
      searchTerm: widget.searchTerm,
    );

    // Sort if a column is selected.
    if (_sortColumnIndex != null) {
      allRows.sort((a, b) {
        final cmp = switch (_sortColumnIndex!) {
          0 => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          1 => a.width.compareTo(b.width),
          2 => (a.direction ?? 'internal').compareTo(b.direction ?? 'internal'),
          3 => (_lookupValue(a) ?? '').compareTo(_lookupValue(b) ?? ''),
          _ => 0,
        };
        return _sortAscending ? cmp : -cmp;
      });
    }

    return Table(
      border: TableBorder.all(),
      columnWidths: const <int, TableColumnWidth>{
        0: FlexColumnWidth(2),
        1: IntrinsicColumnWidth(),
        2: IntrinsicColumnWidth(),
        3: FlexColumnWidth(2),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: <TableRow>[
        TableRow(
          children: List<Widget>.generate(
            tableHeaders.length,
            (index) => _buildSortableHeader(
              text: tableHeaders[index],
              columnIndex: index,
            ),
          ),
        ),
        for (var i = 0; i < allRows.length; i++) ...[
          _generateSignalRow(i, allRows),
          if (_expandedSignals.contains(allRows[i].path()))
            ..._generateSubFieldRows(allRows[i]),
        ],
      ],
    );
  }

  /// Look up the display value for a signal (snapshot or live).
  String? _lookupValue(SignalModel signal) {
    final snapshotData = widget.snapshot;
    if (snapshotData != null) {
      final ss = snapshotData.getSignal(signal.path()) ??
          snapshotData.getSignalByName(signal.name);
      if (ss?.value != null) {
        return ss!.value;
      }
    }
    return signal.value;
  }

  /// Collect filtered signals as a single flat list.
  List<SignalModel> _collectSignals(
    TreeModel module, {
    required bool inputSelected,
    required bool outputSelected,
    required bool inoutSelected,
    bool internalsSelected = false,
    String? searchTerm,
  }) {
    final result = <SignalModel>[];
    if (inputSelected) {
      result.addAll(_filterSignals(module.inputs, searchTerm ?? ''));
    }
    if (outputSelected) {
      result.addAll(_filterSignals(module.outputs, searchTerm ?? ''));
    }
    if (inoutSelected) {
      result.addAll(_filterSignals(module.inouts, searchTerm ?? ''));
    }
    if (internalsSelected) {
      // Collect sub-field names from struct/array parents so we keep only
      // top-level LogicArrays and LogicStructures (user can expand them
      // via the caret).
      final allInternals =
          module.signals.where((s) => s.direction == null).toList();
      final subFieldNames = <String>{};
      for (final s in allInternals) {
        if (s.isStruct || s.isArray) {
          for (final d in s.subFieldDescriptors) {
            subFieldNames.add(d.expectedName);
          }
        }
      }
      result.addAll(
        _filterSignals(
          allInternals.where((s) => !subFieldNames.contains(s.name)).toList(),
          searchTerm ?? '',
        ),
      );
    }
    return result;
  }

  TableRow _generateSignalRow(int index, List<SignalModel> allRows) {
    final signal = allRows[index];
    final isSelected = _selectedIndices.contains(index);

    // Look up snapshot value: try by hierarchy path first, then by name
    final snapshotData = widget.snapshot;
    SignalSnapshot? snapshotSignal;
    if (snapshotData != null) {
      snapshotSignal = snapshotData.getSignal(signal.path()) ??
          snapshotData.getSignalByName(signal.name);
    }
    var snapshotValue = snapshotSignal?.value;
    var isComputed = snapshotSignal?.computed ?? false;

    // Fallback: evaluate via client-side netlist evaluator when the
    // snapshot doesn't contain the signal (untracked / computed).
    // A signal present in the snapshot has an authoritative value —
    // even 'x', which is a valid simulation value (unknown/don't-care).
    if (snapshotValue == null && widget.signalValueFallback != null) {
      final eval = widget.signalValueFallback!(signal.path());
      if (eval != null) {
        snapshotValue = eval.value;
        isComputed = eval.computed;
      }
    }

    final displayValue = snapshotValue ?? signal.value;
    final isSnapshotValue = snapshotValue != null;
    final selectedIndices =
        _selectedIndices.contains(index) ? _selectedIndices : {index};
    void setSelectedFormat(MonitorValueFormat format) {
      SignalValueFormatRegistry.setFormatFor(
        selectedIndices
            .where((selectedIndex) => selectedIndex < allRows.length)
            .map((selectedIndex) => allRows[selectedIndex].address)
            .whereType<OccurrenceAddress>(),
        SignalValueFormatRegistry.formatFromString(format.name)!,
      );
    }

    // Determine which signals to send (selected set, or just this row).
    VoidCallback? sendHandler;
    String sendLabel;
    if (widget.onSendSignals != null) {
      sendLabel = selectedIndices.length > 1
          ? 'Send ${selectedIndices.length} Signals'
          : 'Send Signal';
      sendHandler = () {
        final paths = selectedIndices
            .where((i) => i < allRows.length)
            .map((i) => allRows[i].path())
            .toList();
        widget.onSendSignals!(paths);
      };
    } else {
      sendLabel = 'Send Signal';
    }

    // Determine the paths to navigate to (selected set, or just this row).
    List<String>? goToPaths;
    if (widget.onGoToSource != null) {
      goToPaths = selectedIndices
          .where((i) => i < allRows.length)
          .map((i) => allRows[i].path())
          .toList();
    }

    Widget wrapTap(Widget child) =>
        GestureDetector(onTap: () => _onRowTap(index), child: child);

    final formattedValue = SignalValueFormatRegistry.formatValue(
      _formatValue(displayValue, width: signal.width),
      SignalValueFormatRegistry.formatForAny([signal.address]),
      signal.width,
    );

    return TableRow(
      decoration: isSelected
          ? BoxDecoration(
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
            )
          : null,
      children: <Widget>[
        wrapTap(
          _CopyableCell(
            copyText: signal.name,
            fullPathText: signal.path(),
            tooltip: 'Right-click to copy or send signal',
            onSend: sendHandler,
            sendLabel: sendLabel,
            signalName: signal.name,
            signalPath: signal.path(),
            signalWidth: signal.width,
            onSendPaths: widget.onSendSignals,
            onGoToSource: widget.onGoToSource,
            availableSourceFormats: widget.availableSourceFormats,
            goToPaths: goToPaths,
            onSetFormat: setSelectedFormat,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (signal.isStruct || signal.isArray)
                  GestureDetector(
                    onTapUp: (details) {
                      final path = signal.path();
                      if (_expandedSignals.contains(path)) {
                        setState(() {
                          _expandedSignals.remove(path);
                          // Also collapse all sub-field expansions beneath.
                          _expandedSubFields.removeWhere(
                            (k) => k.startsWith('$path/'),
                          );
                        });
                      } else {
                        final keys =
                            HardwareKeyboard.instance.logicalKeysPressed;
                        final isShift =
                            keys.contains(LogicalKeyboardKey.shiftLeft) ||
                                keys.contains(LogicalKeyboardKey.shiftRight);
                        if (isShift) {
                          _expandFullyFromSignal(signal);
                        } else {
                          unawaited(
                            _showExpandPopup(
                              context,
                              signal: signal,
                              tapPosition: details.globalPosition,
                            ),
                          );
                        }
                      }
                    },
                    child: Icon(
                      _expandedSignals.contains(signal.path())
                          ? Icons.expand_more
                          : Icons.chevron_right,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  )
                else
                  const SizedBox(width: 16),
                Flexible(child: Text(signal.name)),
              ],
            ),
          ),
        ),
        wrapTap(
          SizedBox(
            height: 32,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(signal.width.toString()),
              ),
            ),
          ),
        ),
        wrapTap(
          SizedBox(
            height: 32,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(signal.direction ?? 'internal'),
              ),
            ),
          ),
        ),
        wrapTap(
          _CopyableCell(
            copyText: formattedValue,
            tooltip: 'Right-click to copy value',
            onSetFormat: setSelectedFormat,
            child: Text(
              formattedValue,
              style: isSnapshotValue
                  ? TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isComputed
                          ? const Color(0xFFFFD54F)
                          : Theme.of(context).colorScheme.primary,
                    )
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  /// Generate expanded sub-field rows for a struct/array signal.
  ///
  /// Only shows one hierarchy level at a time. Sub-fields that have children
  /// get their own expand caret — clicking it expands the next level.
  List<TableRow> _generateSubFieldRows(SignalModel signal) {
    final logicType = signal.logicType;
    if (logicType == null) {
      return const [];
    }

    // Get binary value from the signal's current value.
    final rawValue = _lookupValue(signal);
    String? binaryValue;
    if (rawValue != null) {
      final rawHex = _extractRawHex(rawValue);
      if (rawHex != null) {
        binaryValue = hexToBinary(rawHex, signal.width);
      }
    }

    final nodes = expandLogicType(logicType, parentBinaryValue: binaryValue);
    if (nodes.isEmpty) {
      return const [];
    }

    final basePath = signal.path();
    final rows = <TableRow>[];
    for (final node in nodes) {
      _collectSubFieldRows(
        rows,
        node,
        indent: 1,
        parentKey: basePath,
        baseOffset: 0,
        direction: signal.direction,
        topSignalPath: basePath,
        parentSanitized: signal.name,
      );
    }
    return rows;
  }

  /// Collect table rows for a [TypeFieldNode] tree, expanding one level at a
  /// time.  Sub-fields with children show an expand caret; clicking it adds
  /// their sub-field key to [_expandedSubFields].
  ///
  /// [baseOffset] is the absolute bit offset of the parent within the
  /// top-level signal, so nested fields display their true bit position.
  void _collectSubFieldRows(
    List<TableRow> rows,
    TypeFieldNode node, {
    required int indent,
    required String parentKey,
    required int baseOffset,
    required String topSignalPath,
    required String parentSanitized,
    String? direction,
  }) {
    final nodeKey = '$parentKey/${node.name}';
    final hasChildren = node.children.isNotEmpty;
    final isExpanded = _expandedSubFields.contains(nodeKey);
    final isSelectedSub = _selectedSubFieldKey == nodeKey;

    // Full sanitized wire name for this sub-field, following the ROHD
    // flattening convention (`{parent}_{field}` for struct fields,
    // `{parent}_{i}_` for array elements).  This matches the real netlist
    // wire (e.g. `a_mantissa`) so the schematic and waveform viewers can
    // resolve it.  The short `node.name` is used only for on-screen display.
    final nodeSanitized = _sanitizedChildName(parentSanitized, node);

    // When sending, replace the top signal's last path segment with the
    // sub-field's full sanitized name so the ID is a meaningful wire path
    // (e.g. `top/mod/a_mantissa`) rather than a bit slice.
    final slash = topSignalPath.lastIndexOf('/');
    final parentDir = slash >= 0 ? topSignalPath.substring(0, slash + 1) : '';
    final sendPaths = <String>['$parentDir$nodeSanitized'];

    final valueStr = formatFieldValue(node.value, node.width);

    // Wrap a cell so the whole sub-field row is selectable (left-click) and
    // exposes a context menu (right-click).  The inner expand-caret keeps its
    // own tap handler — it wins the gesture arena over this outer tap.
    Widget wrap(Widget child) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _onSubFieldTap(nodeKey),
          onSecondaryTapUp: (details) => unawaited(
            _showSubFieldMenu(
              context,
              details.globalPosition,
              fieldName: node.name,
              fullPath: sendPaths.first,
              fieldValue: valueStr,
              sendPaths: sendPaths,
            ),
          ),
          child: child,
        );

    final bitFieldStr = BitFieldUtils.formatBitRange(
      node.startBit + baseOffset,
      node.width,
    );

    rows.add(
      TableRow(
        decoration: BoxDecoration(
          color: isSelectedSub
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.18)
              : Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.3),
        ),
        children: <Widget>[
          wrap(
            Padding(
              padding: EdgeInsets.only(left: 8.0 + indent * 16.0),
              child: SizedBox(
                height: 28,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasChildren)
                        GestureDetector(
                          onTapUp: (details) {
                            if (isExpanded) {
                              setState(() {
                                _expandedSubFields
                                  ..remove(nodeKey)
                                  // Collapse descendants.
                                  ..removeWhere(
                                    (k) => k.startsWith('$nodeKey/'),
                                  );
                              });
                            } else {
                              final keys =
                                  HardwareKeyboard.instance.logicalKeysPressed;
                              final isShift = keys
                                      .contains(LogicalKeyboardKey.shiftLeft) ||
                                  keys.contains(LogicalKeyboardKey.shiftRight);
                              if (isShift) {
                                setState(() {
                                  _expandedSubFields.add(nodeKey);
                                  _expandAllDescendants(node, nodeKey);
                                });
                              } else {
                                unawaited(
                                  _showSubFieldExpandPopup(
                                    context,
                                    node: node,
                                    nodeKey: nodeKey,
                                    tapPosition: details.globalPosition,
                                  ),
                                );
                              }
                            }
                          },
                          child: Icon(
                            isExpanded
                                ? Icons.expand_more
                                : Icons.chevron_right,
                            size: 14,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      Flexible(
                        child: Text(
                          node.name,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).hintColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          wrap(
            SizedBox(
              height: 28,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: baseOffset > 0
                      ? Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: BitFieldUtils.formatBitRange(
                                  node.startBit + baseOffset,
                                  node.width,
                                ),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).hintColor,
                                ),
                              ),
                              TextSpan(
                                text: ' ($bitFieldStr)',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Theme.of(context)
                                      .hintColor
                                      .withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                          ),
                        )
                      : Text(
                          BitFieldUtils.formatBitRange(
                            node.startBit,
                            node.width,
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).hintColor,
                          ),
                        ),
                ),
              ),
            ),
          ),
          wrap(
            SizedBox(
              height: 28,
              child: direction != null
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          direction,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).hintColor,
                          ),
                        ),
                      ),
                    )
                  : null,
            ),
          ),
          wrap(
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                height: 28,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    valueStr,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    // Show the next level only if this sub-field is expanded.
    if (isExpanded) {
      for (final child in node.children) {
        _collectSubFieldRows(
          rows,
          child,
          indent: indent + 1,
          parentKey: nodeKey,
          baseOffset: baseOffset + node.startBit,
          direction: direction,
          topSignalPath: topSignalPath,
          parentSanitized: nodeSanitized,
        );
      }
    }
  }

  /// Derive the full sanitized wire name of a sub-field [node] from its
  /// parent's sanitized name, following ROHD's flattening convention:
  /// struct fields become `{parent}_{field}` and array elements `[i]`
  /// become `{parent}_{i}_`.
  static String _sanitizedChildName(
    String parentSanitized,
    TypeFieldNode node,
  ) {
    final arrayMatch = regExpFirstMatch(r'^\[(\d+)\]$', node.name);
    if (arrayMatch != null) {
      return '${parentSanitized}_${arrayMatch.group(1)}_';
    }
    return '${parentSanitized}_${node.name}';
  }

  /// Select a sub-field row by its hierarchical [nodeKey], clearing any
  /// top-level row selection so only one kind of selection is active.
  void _onSubFieldTap(String nodeKey) {
    setState(() {
      _selectedIndices.clear();
      _lastClickedIndex = null;
      _selectedSubFieldKey = nodeKey;
    });
  }

  /// Show the right-click context menu for a sub-field row.
  Future<void> _showSubFieldMenu(
    BuildContext context,
    Offset position, {
    required String fieldName,
    required String fullPath,
    required String fieldValue,
    required List<String> sendPaths,
  }) async {
    final canSend = widget.onSendSignals != null && sendPaths.isNotEmpty;
    final canGoToSource = widget.onGoToSource != null && sendPaths.isNotEmpty;
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
          value: 'copy',
          height: 32,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.copy, size: 16),
              SizedBox(width: 8),
              Text('Copy Name'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'copy_path',
          height: 32,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.copy_all, size: 16),
              SizedBox(width: 8),
              Text('Copy Full Path'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'copy_value',
          height: 32,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.content_paste, size: 16),
              SizedBox(width: 8),
              Text('Copy Value'),
            ],
          ),
        ),
        if (canSend) ...[
          const PopupMenuDivider(height: 8),
          const PopupMenuItem<String>(
            value: 'send',
            height: 32,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.send, size: 16),
                SizedBox(width: 8),
                Text('Send Field'),
              ],
            ),
          ),
        ],
        if (canGoToSource) ...[
          const PopupMenuDivider(height: 8),
          ...buildGotoSourceMenuItems(
            formats: widget.availableSourceFormats?.call() ??
                kDefaultNavigableFormats,
          ),
        ],
      ],
    );

    if (!context.mounted) {
      return;
    }
    final gotoFormat = gotoSourceFormatFromValue(value);
    if (gotoFormat != null) {
      widget.onGoToSource?.call(gotoFormat, sendPaths);
      return;
    }
    switch (value) {
      case 'copy':
        unawaited(Clipboard.setData(ClipboardData(text: fieldName)));
      case 'copy_path':
        unawaited(Clipboard.setData(ClipboardData(text: fullPath)));
      case 'copy_value':
        unawaited(Clipboard.setData(ClipboardData(text: fieldValue)));
      case 'send':
        widget.onSendSignals?.call(sendPaths);
    }
  }

  // ---------------------------------------------------------------------------
  // Recursive expansion helpers
  // ---------------------------------------------------------------------------

  /// Recursively add all descendant node keys to [_expandedSubFields].
  void _expandAllDescendants(TypeFieldNode node, String parentKey) {
    for (final child in node.children) {
      final childKey = '$parentKey/${child.name}';
      if (child.children.isNotEmpty) {
        _expandedSubFields.add(childKey);
        _expandAllDescendants(child, childKey);
      }
    }
  }

  /// Expand a top-level signal and all its sub-field descendants.
  void _expandFullyFromSignal(SignalModel signal) {
    final logicType = signal.logicType;
    if (logicType == null) {
      return;
    }

    final rawValue = _lookupValue(signal);
    String? binaryValue;
    if (rawValue != null) {
      final rawHex = _extractRawHex(rawValue);
      if (rawHex != null) {
        binaryValue = hexToBinary(rawHex, signal.width);
      }
    }

    final nodes = expandLogicType(logicType, parentBinaryValue: binaryValue);
    final basePath = signal.path();
    setState(() {
      _expandedSignals.add(basePath);
      for (final node in nodes) {
        final nodeKey = '$basePath/${node.name}';
        if (node.children.isNotEmpty) {
          _expandedSubFields.add(nodeKey);
          _expandAllDescendants(node, nodeKey);
        }
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Pop-up menus for hierarchical expansion
  // ---------------------------------------------------------------------------

  /// Show a pop-up menu to expand a top-level struct/array signal.
  ///
  /// If the number of direct children exceeds the expand threshold, presents a
  /// confirmation menu (with range selection for arrays).  Otherwise expands
  /// immediately.
  Future<void> _showExpandPopup(
    BuildContext context, {
    required SignalModel signal,
    required Offset tapPosition,
  }) async {
    final logicType = signal.logicType;
    if (logicType == null) {
      return;
    }

    final numFields = _countDirectChildren(logicType);
    if (numFields <= BitFieldUtils.expandThreshold) {
      // Small enough — expand immediately.
      setState(() => _expandedSignals.add(signal.path()));
      return;
    }

    // Show a confirmation/range popup.
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final local = overlay.globalToLocal(tapPosition);

    final isArray = logicType.containsKey('arrayDims');
    final items = <PopupMenuEntry<dynamic>>[
      PopupMenuItem<String>(
        height: 32,
        value: 'expand',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.unfold_more, size: 14),
            const SizedBox(width: 8),
            Text(
              'Expand ($numFields ${isArray ? "elements" : "fields"})',
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
      if (isArray)
        PopupMenuItem<String>(
          height: 32,
          value: 'range',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.linear_scale, size: 14),
              const SizedBox(width: 8),
              Text(
                'Select Range (0:${numFields - 1})...',
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
      const PopupMenuItem<String>(
        height: 32,
        value: 'cancel',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.close, size: 14),
            SizedBox(width: 8),
            Text('Cancel', style: TextStyle(fontSize: 13)),
          ],
        ),
      ),
    ];

    final value = await showMenu<dynamic>(
      context: context,
      position: RelativeRect.fromLTRB(
        local.dx,
        local.dy + 24,
        overlay.size.width - local.dx - 200,
        overlay.size.height - local.dy - 24,
      ),
      items: items,
    );

    if (value == null || value == 'cancel' || !mounted) {
      return;
    }
    if (value == 'expand') {
      setState(() => _expandedSignals.add(signal.path()));
    } else if (value == 'range') {
      await _showRangeDialog(
        this.context,
        signalPath: signal.path(),
        maxIndex: numFields - 1,
        signalName: signal.name,
      );
    }
  }

  /// Show a pop-up menu to expand a nested sub-field node.
  ///
  /// If the child count exceeds the expand threshold, asks for confirmation.
  /// Otherwise expands immediately.
  Future<void> _showSubFieldExpandPopup(
    BuildContext context, {
    required TypeFieldNode node,
    required String nodeKey,
    required Offset tapPosition,
  }) async {
    final numChildren = node.children.length;
    if (numChildren <= BitFieldUtils.expandThreshold) {
      setState(() => _expandedSubFields.add(nodeKey));
      return;
    }

    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final local = overlay.globalToLocal(tapPosition);

    // Determine if the children look like array elements (names are "[n]").
    final isArrayLike =
        node.children.isNotEmpty && node.children.first.name.startsWith('[');

    final items = <PopupMenuEntry<dynamic>>[
      PopupMenuItem<String>(
        height: 32,
        value: 'expand',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.unfold_more, size: 14),
            const SizedBox(width: 8),
            Text(
              'Expand ($numChildren ${isArrayLike ? "elements" : "fields"})',
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
      const PopupMenuItem<String>(
        height: 32,
        value: 'cancel',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.close, size: 14),
            SizedBox(width: 8),
            Text('Cancel', style: TextStyle(fontSize: 13)),
          ],
        ),
      ),
    ];

    final value = await showMenu<dynamic>(
      context: context,
      position: RelativeRect.fromLTRB(
        local.dx,
        local.dy + 24,
        overlay.size.width - local.dx - 200,
        overlay.size.height - local.dy - 24,
      ),
      items: items,
    );

    if (value == null || value == 'cancel' || !mounted) {
      return;
    }
    if (value == 'expand') {
      setState(() => _expandedSubFields.add(nodeKey));
    }
  }

  /// Show a dialog to select a range of array indices to expand.
  Future<void> _showRangeDialog(
    BuildContext context, {
    required String signalPath,
    required int maxIndex,
    required String signalName,
  }) async {
    final controller = TextEditingController(text: '0:$maxIndex');
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );

    final result = await showDialog<String>(
      context: context,
      barrierColor: Colors.black26,
      builder: (ctx) => AlertDialog(
        title: Text(
          '$signalName  [${maxIndex + 1} elements]',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Range (start:end) or single index',
            hintText: '0:$maxIndex',
            isDense: true,
          ),
          onSubmitted: (value) => Navigator.of(ctx).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    if (result == null || result.trim().isEmpty || !mounted) {
      return;
    }
    // Parse and expand only the selected range of sub-fields.
    // We expand the signal and let the rendering handle visibility.
    setState(() => _expandedSignals.add(signalPath));
  }

  /// Count the number of direct children for a given logicType.
  static int _countDirectChildren(Map<String, dynamic> logicType) {
    final fields = logicType['fields'] as List<dynamic>?;
    if (fields != null) {
      return fields.length;
    }
    final arrayDims = logicType['arrayDims'] as List<dynamic>?;
    if (arrayDims != null && arrayDims.isNotEmpty) {
      return arrayDims[0] as int;
    }
    return 0;
  }

  /// Extract raw hex from a formatted value string.
  ///
  /// Handles formats like "16'hfffe", "0xff", or bare hex.
  static String? _extractRawHex(String value) {
    // ROHD radixString: width'hHEX
    final radixMatch = regExpFirstMatch(r"^\d+'h([0-9a-fA-Fxz]+)$", value);
    if (radixMatch != null) {
      return radixMatch.group(1);
    }

    // 0x prefix
    if (value.toLowerCase().startsWith('0x')) {
      return value.substring(2);
    }

    // Try as bare hex
    if (regExpHasMatch(r'^[0-9a-fA-F]+$', value)) {
      return value;
    }

    return null;
  }

  Widget _buildSortableHeader({
    required String text,
    required int columnIndex,
  }) {
    final isSorted = _sortColumnIndex == columnIndex;
    return InkWell(
      onTap: () {
        setState(() {
          if (_sortColumnIndex == columnIndex) {
            if (_sortAscending) {
              _sortAscending = false;
            } else {
              // Third click clears the sort.
              _sortColumnIndex = null;
            }
          } else {
            _sortColumnIndex = columnIndex;
            _sortAscending = true;
          }
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: SizedBox(
          height: 32,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  text,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                if (isSorted)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(
                      _sortAscending
                          ? Icons.arrow_upward
                          : Icons.arrow_downward,
                      size: 14,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A table cell that shows a context menu with "Copy" (and optionally "Send")
/// on right-click.
class _CopyableCell extends StatelessWidget {
  const _CopyableCell({
    required this.copyText,
    required this.child,
    this.fullPathText,
    this.tooltip,
    this.onSend,
    this.sendLabel,
    this.signalName,
    this.signalPath,
    this.signalWidth,
    this.onSendPaths,
    this.onGoToSource,
    this.availableSourceFormats,
    this.goToPaths,
    void Function(MonitorValueFormat format)? onSetFormat,
  }) : _onSetFormat = onSetFormat;

  final String copyText;
  final Widget child;

  /// When non-null, a "Copy Full Path" menu item is shown.
  final String? fullPathText;
  final String? tooltip;

  /// When non-null, a "Send Signal(s)" menu item is shown in the context menu.
  final VoidCallback? onSend;

  /// Label for the send menu item (e.g. "Send SignalOccurrence" or "Send 3
  /// Signals").
  final String? sendLabel;

  /// Display name of the signal, used in the bit-expansion dialogs.
  final String? signalName;

  /// Full hierarchical path of the signal; used as the parent of the
  /// synthesized `path#b[...]` bit-slice IDs.
  final String? signalPath;

  /// Width of the signal in bits; bit-expansion items are only shown when
  /// this is `> 1`.
  final int? signalWidth;

  /// Callback used to forward the encoded `path#b[...]` IDs produced by the
  /// bit-expansion items to the host (typically [SignalTable.onSendSignals]).
  final void Function(List<String> signalPaths)? onSendPaths;

  /// Callback to navigate to a signal's source for a chosen [RohdSourceFormat].
  final GoToSourceCallback? onGoToSource;

  /// Discovers which source formats are navigable for the current module.
  final AvailableSourceFormats? availableSourceFormats;

  /// Signal paths to navigate to when a "Go to … Source" item is chosen.
  final List<String>? goToPaths;

  final void Function(MonitorValueFormat format)? _onSetFormat;

  bool get _canBitExpand =>
      onSendPaths != null &&
      signalName != null &&
      signalPath != null &&
      signalWidth != null &&
      signalWidth! > 1;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onSecondaryTapUp: (details) {
          _showCopyMenu(context, details.globalPosition);
        },
        onLongPressStart: (details) {
          _showCopyMenu(context, details.globalPosition);
        },
        child: Tooltip(
          message: tooltip ?? '',
          waitDuration: const Duration(milliseconds: 600),
          child: SizedBox(
            height: 32,
            child: Align(alignment: Alignment.centerLeft, child: child),
          ),
        ),
      );

  void _showCopyMenu(BuildContext context, Offset position) {
    final items = <PopupMenuEntry<String>>[
      const PopupMenuItem<String>(
        value: 'copy',
        height: 32,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.copy, size: 16),
            SizedBox(width: 8),
            Text('Copy'),
          ],
        ),
      ),
      if (fullPathText != null)
        const PopupMenuItem<String>(
          value: 'copy_path',
          height: 32,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.copy_all, size: 16),
              SizedBox(width: 8),
              Text('Copy Full Path'),
            ],
          ),
        ),
      if (onSend != null) ...[
        const PopupMenuDivider(height: 8),
        PopupMenuItem<String>(
          value: 'send',
          height: 32,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.send, size: 16),
              const SizedBox(width: 8),
              Text(sendLabel ?? 'Send Signal'),
            ],
          ),
        ),
      ],
      if (onGoToSource != null &&
          goToPaths != null &&
          goToPaths!.isNotEmpty) ...[
        const PopupMenuDivider(height: 8),
        ...buildGotoSourceMenuItems(
          formats: availableSourceFormats?.call() ?? kDefaultNavigableFormats,
          count: goToPaths!.length,
        ),
      ],
      if (_onSetFormat != null) ...[
        const PopupMenuDivider(height: 8),
        const PopupMenuItem<String>(
          value: signalFormatMenuValue,
          height: 32,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.numbers, size: 16),
              SizedBox(width: 8),
              Text('Format As'),
            ],
          ),
        ),
      ],
      if (_canBitExpand)
        ...buildBitExpansionMenuItems(
          width: signalWidth!,
          fontSize: 14,
          includeDivider: onSend == null,
        ),
    ];

    unawaited(
      showMenu<String>(
        context: context,
        position: RelativeRect.fromLTRB(
          position.dx,
          position.dy,
          position.dx,
          position.dy,
        ),
        items: items,
      ).then((value) async {
        if (value == 'copy' || value == 'copy_path') {
          final text =
              value == 'copy_path' ? (fullPathText ?? copyText) : copyText;
          unawaited(Clipboard.setData(ClipboardData(text: text)));
          if (!context.mounted) {
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Copied: $text'),
              duration: const Duration(seconds: 1),
              behavior: SnackBarBehavior.floating,
              width: 250,
            ),
          );
        } else if (value == 'send') {
          onSend?.call();
        } else if (value == signalFormatMenuValue) {
          final paths = goToPaths ??
              (signalPath == null ? const <String>[] : [signalPath!]);
          if (paths.isNotEmpty && context.mounted) {
            await showSignalFormatMenu(
              context,
              globalPosition: position,
              signalPaths: paths.toSet(),
              onFormatSelected: _onSetFormat,
            );
          }
        } else if (gotoSourceFormatFromValue(value) != null) {
          final fmt = gotoSourceFormatFromValue(value)!;
          final paths = goToPaths;
          if (paths != null && paths.isNotEmpty) {
            onGoToSource?.call(fmt, paths);
          }
        } else if (_canBitExpand) {
          if (!context.mounted) {
            return;
          }
          final action = await resolveBitExpansionMenuValue(
            context,
            value: value,
            signalName: signalName!,
            width: signalWidth!,
          );
          if (action == null) {
            return;
          }
          final List<String> paths;
          switch (action) {
            case BitExpandRangeAction(:final bitStart, :final bitEnd):
              paths = [
                for (var b = bitStart; b <= bitEnd; b++) '$signalPath#b[$b]',
              ];
            case BitDefineFieldsAction(:final fields):
              paths = [
                for (final f in fields)
                  if (f.high == f.low)
                    '$signalPath#b[${f.low}]'
                  else
                    '$signalPath#b[${f.high}:${f.low}]',
              ];
          }
          if (paths.isNotEmpty) {
            onSendPaths?.call(paths);
          }
        }
      }),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(StringProperty('copyText', copyText))
      ..add(StringProperty('fullPathText', fullPathText))
      ..add(StringProperty('tooltip', tooltip))
      ..add(ObjectFlagProperty<VoidCallback?>.has('onSend', onSend))
      ..add(StringProperty('sendLabel', sendLabel))
      ..add(StringProperty('signalName', signalName))
      ..add(StringProperty('signalPath', signalPath))
      ..add(IntProperty('signalWidth', signalWidth))
      ..add(
        ObjectFlagProperty<void Function(List<String> signalPaths)?>.has(
          'onSendPaths',
          onSendPaths,
        ),
      )
      ..add(
        ObjectFlagProperty<GoToSourceCallback?>.has(
          'onGoToSource',
          onGoToSource,
        ),
      )
      ..add(
        ObjectFlagProperty<AvailableSourceFormats?>.has(
          'availableSourceFormats',
          availableSourceFormats,
        ),
      )
      ..add(IterableProperty<String>('goToPaths', goToPaths));
  }
}
