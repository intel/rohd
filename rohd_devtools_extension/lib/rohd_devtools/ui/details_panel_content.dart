// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// details_panel_content.dart
// Shared details panel content widget with tabs.
// Used by both the DevTools extension and standalone entry points.
//
// 2026 January
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cubit/cubits.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/module_tree_details_navbar.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/signal_details_card.dart';
import 'package:rohd_schematic_viewer/schematic_viewer.dart';

/// Configuration for the waveform tab.
class WaveformTabConfig {
  /// The waveform viewer widget.
  final Widget waveformViewer;

  /// Creates a [WaveformTabConfig] with the given waveform viewer.
  const WaveformTabConfig({required this.waveformViewer});
}

/// Configuration for the schematic tab.
class SchematicTabConfig {
  /// Asset path for schematic JSON (without 'assets/' prefix for web).
  final String assetPath;

  /// Custom schematic widget builder (overrides default
  /// `EmbeddedSchematicViewer`).
  ///
  /// The `isVisible` parameter indicates whether the schematic tab is
  /// currently selected. Pass it to `EmbeddedSchematicViewer.isVisible`
  /// so expensive layout work is deferred while the tab is hidden.
  final Widget Function({required bool isVisible})? customWidgetBuilder;

  /// Creates a [SchematicTabConfig] with the given asset path and optional
  /// custom widget builder.
  const SchematicTabConfig({required this.assetPath, this.customWidgetBuilder});
}

/// Shared details panel content with tabbed interface.
///
/// Shows tabs for: Details, Waveform, Schematic, JS Schematic
class DetailsPanelContent extends StatefulWidget {
  /// Configuration for the waveform tab.
  final WaveformTabConfig waveformConfig;

  /// Configuration for the schematic tab.
  final SchematicTabConfig schematicConfig;

  /// Optional placeholder text when no module is selected.
  final String noModuleSelectedText;

  /// Custom details tab widget (overrides default SignalDetailsCard).
  final Widget? customDetailsTab;

  /// Whether the platform supports color emoji.
  /// Defaults to true (works for web). On Linux, check with
  /// `isEmojiFontInstalled`.
  final bool hasColorEmoji;

  /// Optional fallback for signals missing from the snapshot.
  ///
  /// When non-null, the details table calls this for any signal whose value
  /// is absent from the snapshot map (e.g. computed gate outputs).  The
  /// callback should use the client-side netlist evaluator.
  final ({String value, bool computed})? Function(String signalPath)?
      _signalValueFallback;

  /// Called to eagerly expand a module's connectivity (slim → full JSON)
  /// so that the evaluator can compute internal signal values.
  final Future<void> Function(String moduleInstancePath)? _onExpandModule;

  /// Callback to send selected signal paths to waveform/schematic viewers.
  final void Function(List<String> signalPaths)? _onSendSignals;

  /// Callback to navigate to a signal's source for a chosen [RohdSourceFormat].
  final GoToSourceCallback? _onGoToSource;

  /// Discovers which source formats are navigable for the current module.
  final AvailableSourceFormats? _availableSourceFormats;

  /// Creates a [DetailsPanelContent] with the given configurations.
  const DetailsPanelContent({
    required this.waveformConfig,
    required this.schematicConfig,
    super.key,
    this.noModuleSelectedText =
        'Select a module from the tree to view its signals',
    this.customDetailsTab,
    this.hasColorEmoji = true,
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
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(
        DiagnosticsProperty<WaveformTabConfig>(
          'waveformConfig',
          waveformConfig,
        ),
      )
      ..add(
        DiagnosticsProperty<SchematicTabConfig>(
          'schematicConfig',
          schematicConfig,
        ),
      )
      ..add(StringProperty('noModuleSelectedText', noModuleSelectedText))
      ..add(DiagnosticsProperty<Widget?>('customDetailsTab', customDetailsTab))
      ..add(
        FlagProperty(
          'hasColorEmoji',
          value: hasColorEmoji,
          ifFalse: 'using fallback icons',
        ),
      );
  }

  @override
  State<DetailsPanelContent> createState() => _DetailsPanelContentState();
}

class _DetailsPanelContentState extends State<DetailsPanelContent> {
  final ValueNotifier<bool> _overlayTrigger = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _overlayTrigger.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Build children ONCE per build() — not per tab change.
    // Hoisting them out of the BlocBuilder closure ensures Flutter sees the
    // same widget instance when only the tab index changes, avoiding a
    // forced rebuild cascade that would re-evaluate every signal.
    final detailsChild = widget.customDetailsTab ?? _buildDetailsTab(context);
    final waveformChild = widget.waveformConfig.waveformViewer;

    return AppBarOverlayTrigger(
      notifier: _overlayTrigger,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MouseRegion(
            onEnter: (_) => _overlayTrigger.value = true,
            onExit: (_) => _overlayTrigger.value = false,
            child: ModuleTreeDetailsNavbar(hasColorEmoji: widget.hasColorEmoji),
          ),
          Expanded(
            // ClipRect prevents overlay AppBars from painting above the
            // content area into the tab bar when they slide up to hide.
            child: ClipRect(
              child: BlocBuilder<DetailsTabCubit, DetailsTab>(
                builder: (context, selectedTab) => IndexedStack(
                  index: selectedTab.index,
                  children: [
                    // DetailsTab.details (index 0)
                    detailsChild,
                    // DetailsTab.waveform (index 1)
                    waveformChild,
                    // DetailsTab.schematic (index 2)
                    widget.schematicConfig.customWidgetBuilder?.call(
                          isVisible: selectedTab == DetailsTab.schematic,
                        ) ??
                        _buildSchematicTab(
                          context,
                          isVisible: selectedTab == DetailsTab.schematic,
                        ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsTab(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 20, right: 20),
        child: SingleChildScrollView(
          child: BlocBuilder<DevToolsHierarchyCubit, DevToolsHierarchyState>(
            buildWhen: (prev, curr) {
              final prevSel =
                  prev is HierarchyLoaded ? prev.selectedModule : null;
              final currSel =
                  curr is HierarchyLoaded ? curr.selectedModule : null;
              return prevSel != currSel;
            },
            builder: (context, state) {
              final selectedModule =
                  state is HierarchyLoaded ? state.selectedModule : null;
              if (selectedModule != null) {
                return BlocBuilder<SnapshotCubit, SnapshotState>(
                  builder: (context, snapshotState) {
                    final snapshot =
                        snapshotState is SnapshotLoaded ? snapshotState : null;
                    return SignalDetailsCard(
                      module: selectedModule,
                      snapshot: snapshot,
                      signalValueFallback: widget._signalValueFallback,
                      onExpandModule: widget._onExpandModule,
                      onSendSignals: widget._onSendSignals,
                      onGoToSource: widget._onGoToSource,
                      availableSourceFormats: widget._availableSourceFormats,
                    );
                  },
                );
              } else {
                final isDark = Theme.of(context).brightness == Brightness.dark;
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      widget.noModuleSelectedText,
                      style: TextStyle(
                        color: isDark ? Colors.white54 : Colors.black38,
                      ),
                    ),
                  ),
                );
              }
            },
          ),
        ),
      );

  Widget _buildSchematicTab(BuildContext context, {required bool isVisible}) {
    // Get the selected module and hierarchy service from the cubit
    final hierarchyState = context.watch<DevToolsHierarchyCubit>().state;

    final selectedModule = hierarchyState is HierarchyLoaded
        ? hierarchyState.selectedModule
        : null;

    final hierarchyService = hierarchyState is HierarchyLoaded
        ? hierarchyState.hierarchyService
        : null;

    return EmbeddedSchematicViewer(
      // Only use fallback asset path if no hierarchy service is available
      assetPath: hierarchyService == null
          ? (kIsWeb
              ? widget.schematicConfig.assetPath
              : 'assets/${widget.schematicConfig.assetPath}')
          : null,
      externalHierarchy: hierarchyService,
      selectedModule: selectedModule,
      isVisible: isVisible,
      signalValueLookupFn: _buildSignalValueLookup(context),
    );
  }

  /// Build a signal value lookup from the SnapshotCubit, if available.
  ///
  /// The schematic canvas now resolves wire / port names to fully-qualified
  /// hierarchy paths when scope metadata is available.  We therefore try a
  /// direct signal-ID match first, then fall back to a leaf-name match.
  static ({String value, bool computed, String signalId})? Function(
    String wireName,
  )? _buildSignalValueLookup(BuildContext context) {
    final snapshotState = context.watch<SnapshotCubit>().state;
    if (snapshotState is! SnapshotLoaded) {
      return null;
    }

    ({String value, bool computed, String signalId}) hit(SignalSnapshot s) =>
        (value: s.value, computed: s.computed, signalId: s.signalId);

    return (String wireName) {
      // 1. Direct signal-ID match (full hierarchy path).
      final exact = snapshotState.getSignal(wireName);
      if (exact != null) {
        return hit(exact);
      }

      // 2. Fall back to leaf-name match.
      //    When the canvas provides a full path that didn't match (e.g.
      //    type-name rooted), use only the leaf name.
      final leafName = wireName.contains('/')
          ? wireName.substring(wireName.lastIndexOf('/') + 1)
          : wireName;
      final byName = snapshotState.getSignalByName(leafName);
      return byName != null ? hit(byName) : null;
    };
  }
}

/// Wrapper that loads schematic from assets and passes to
/// EmbeddedSchematicViewer.
class _JSSchematicViewerWrapper extends StatefulWidget {
  /// Asset path for schematic JSON (without 'assets/' prefix for web).
  final String assetPath;

  const _JSSchematicViewerWrapper({required this.assetPath});

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('assetPath', assetPath));
  }

  @override
  State<_JSSchematicViewerWrapper> createState() =>
      _JSSchematicViewerWrapperState();
}

class _JSSchematicViewerWrapperState extends State<_JSSchematicViewerWrapper> {
  String? _schematicJson;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSchematic());
  }

  Future<void> _loadSchematic() async {
    try {
      final path = kIsWeb ? widget.assetPath : 'assets/${widget.assetPath}';
      final jsonData = await rootBundle.loadString(path);
      if (mounted) {
        setState(() {
          _schematicJson = jsonData;
          _isLoading = false;
        });
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load schematic: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Text(_error!, style: const TextStyle(color: Colors.red)),
      );
    }

    return EmbeddedSchematicViewer(schematicJson: _schematicJson);
  }
}
