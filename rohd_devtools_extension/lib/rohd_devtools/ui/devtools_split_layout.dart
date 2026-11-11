// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// devtools_split_layout.dart
// Shared split layout widget for DevTools extension.
// Used by both the DevTools extension and standalone entry points.
//
// 2026 January
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cubit/cubits.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/module_search_overlay.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart';

/// Configuration for the left panel (module tree).
class ModuleTreePanelConfig {
  /// Icon widget for the tree header.
  final Widget icon;

  /// Refresh button icon widget.
  final Widget refreshIcon;

  /// Callback when refresh is pressed.
  final VoidCallback? onRefresh;

  /// The module tree content widget.
  final Widget treeContent;

  /// Scroll controllers for the tree content.
  final ScrollController verticalController;

  /// Horizontal scroll controller for the tree content.
  final ScrollController horizontalController;

  /// Optional hierarchy service for incremental search.
  /// If provided, enables the module search field.
  final HierarchyService? hierarchyService;

  /// Creates a [ModuleTreePanelConfig] with the given parameters.
  const ModuleTreePanelConfig({
    required this.icon,
    required this.refreshIcon,
    required this.onRefresh,
    required this.treeContent,
    required this.verticalController,
    required this.horizontalController,
    this.hierarchyService,
  });
}

/// Configuration for the right panel (details/tabs).
class DetailsPanelConfig {
  /// The content widget for the details panel.
  final Widget content;

  /// Creates a [DetailsPanelConfig] with the given content.
  const DetailsPanelConfig({required this.content});
}

/// Shared split layout for ROHD DevTools.
///
/// This widget provides the two-panel layout with a resizable divider:
/// - Left panel: Module tree with search and refresh
/// - Right panel: Details/waveform/schematic tabs
/// - Optional bottom panel: Full-width content with a resizable divider
///
/// Usage:
/// ```dart
/// DevToolsSplitLayout(
///   moduleTreeConfig: ModuleTreePanelConfig(
///     icon: Icon(Icons.account_tree),
///     refreshIcon: Icon(Icons.refresh),
///     onRefresh: () => loadTree(),
///     treeContent: MyTreeWidget(),
///     verticalController: _verticalController,
///     horizontalController: _horizontalController,
///   ),
///   detailsConfig: DetailsPanelConfig(
///     content: MyDetailsWidget(),
///   ),
/// )
/// ```
class DevToolsSplitLayout extends StatelessWidget {
  /// Configuration for the module tree panel.
  final ModuleTreePanelConfig moduleTreeConfig;

  /// Configuration for the details panel.
  final DetailsPanelConfig detailsConfig;

  /// Optional full-width panel displayed beneath the tree and details panels.
  final Widget? bottomContent;

  /// Initial height reserved for [bottomContent].
  final double bottomContentHeight;

  /// Initial fractions for the split pane.
  final List<double> initialFractions;

  /// Minimum sizes for each panel.
  final List<double> minSizes;

  /// Padding around the entire layout.
  final EdgeInsets padding;

  /// Creates a [DevToolsSplitLayout] with the given configurations.
  const DevToolsSplitLayout({
    required this.moduleTreeConfig,
    required this.detailsConfig,
    super.key,
    this.bottomContent,
    this.bottomContentHeight = 260,
    this.initialFractions = const [0.23, 0.77],
    this.minSizes = const [100, 200],
    this.padding = const EdgeInsets.all(10),
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: _buildContent(context),
      );

  Widget _buildContent(BuildContext context) {
    final topContent = _TwoPaneLayout(
      initialFractions: initialFractions,
      minSizes: minSizes,
      children: [
        _buildModuleTreePanel(context),
        _buildDetailsPanel(context),
      ],
    );
    final bottom = bottomContent;
    if (bottom == null) {
      return topContent;
    }
    return _VerticalSplitLayout(
      initialBottomHeight: bottomContentHeight,
      topContent: topContent,
      bottomContent: Card(clipBehavior: Clip.antiAlias, child: bottom),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(
        DiagnosticsProperty<ModuleTreePanelConfig>(
          'moduleTreeConfig',
          moduleTreeConfig,
        ),
      )
      ..add(
        DiagnosticsProperty<DetailsPanelConfig>('detailsConfig', detailsConfig),
      )
      ..add(DoubleProperty('bottomContentHeight', bottomContentHeight))
      ..add(IterableProperty<double>('initialFractions', initialFractions))
      ..add(IterableProperty<double>('minSizes', minSizes))
      ..add(DiagnosticsProperty<EdgeInsets>('padding', padding));
  }

  Widget _buildModuleTreePanel(BuildContext context) =>
      _ModuleTreePanel(config: moduleTreeConfig);

  Widget _buildDetailsPanel(BuildContext context) =>
      Card(clipBehavior: Clip.antiAlias, child: detailsConfig.content);
}

class _ModuleTreePanel extends StatelessWidget {
  const _ModuleTreePanel({required this.config});

  final ModuleTreePanelConfig config;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      DiagnosticsProperty<ModuleTreePanelConfig>('config', config),
    );
  }

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  config.icon,
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Module Tree',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: config.refreshIcon,
                    onPressed: config.onRefresh,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: ModuleSearchField(
                hierarchy: config.hierarchyService,
                onSearchTermChanged: (term) {
                  context.read<TreeSearchTermCubit>().setTerm(term);
                },
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Scrollbar(
                controller: config.verticalController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: config.verticalController,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    controller: config.horizontalController,
                    child: config.treeContent,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}

class _VerticalSplitLayout extends StatefulWidget {
  const _VerticalSplitLayout({
    required this.initialBottomHeight,
    required this.topContent,
    required this.bottomContent,
  });

  final double initialBottomHeight;
  final Widget topContent;
  final Widget bottomContent;

  @override
  State<_VerticalSplitLayout> createState() => _VerticalSplitLayoutState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DoubleProperty('initialBottomHeight', initialBottomHeight));
  }
}

class _VerticalSplitLayoutState extends State<_VerticalSplitLayout> {
  static const _dividerHeight = 8.0;
  static const _minimumTopHeight = 160.0;
  static const _minimumBottomHeight = 140.0;
  double? _bottomHeight;
  double? _dragStartBottomHeight;
  double? _dragStartGlobalY;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final availableHeight = (constraints.maxHeight - _dividerHeight)
              .clamp(0.0, double.infinity);
          final minBottom =
              _minimumBottomHeight.clamp(0.0, availableHeight / 2);
          final minTop = _minimumTopHeight.clamp(0.0, availableHeight / 2);
          final maxBottom = availableHeight - minTop;
          final bottomHeight = (_bottomHeight ?? widget.initialBottomHeight)
              .clamp(minBottom, maxBottom);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: widget.topContent),
              MouseRegion(
                cursor: SystemMouseCursors.resizeUpDown,
                child: GestureDetector(
                  key: const ValueKey('shell-resize-divider'),
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragStart: (details) {
                    _dragStartBottomHeight = bottomHeight;
                    _dragStartGlobalY = details.globalPosition.dy;
                  },
                  onVerticalDragUpdate: (details) {
                    final startHeight = _dragStartBottomHeight;
                    final startY = _dragStartGlobalY;
                    if (startHeight == null || startY == null) {
                      return;
                    }
                    setState(() {
                      _bottomHeight =
                          (startHeight - (details.globalPosition.dy - startY))
                              .clamp(minBottom, maxBottom);
                    });
                  },
                  onVerticalDragEnd: (_) {
                    _dragStartBottomHeight = null;
                    _dragStartGlobalY = null;
                  },
                  child: Container(
                    height: _dividerHeight,
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    alignment: Alignment.center,
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
              ),
              SizedBox(height: bottomHeight, child: widget.bottomContent),
            ],
          );
        },
      );
}

class _TwoPaneLayout extends StatefulWidget {
  final List<double> _initialFractions;
  final List<double> _minSizes;
  final List<Widget> _children;

  const _TwoPaneLayout({
    required List<double> initialFractions,
    required List<double> minSizes,
    required List<Widget> children,
  })  : _initialFractions = initialFractions,
        _minSizes = minSizes,
        _children = children;

  @override
  State<_TwoPaneLayout> createState() => _TwoPaneLayoutState();
}

class _TwoPaneLayoutState extends State<_TwoPaneLayout> {
  static const _dividerWidth = 8.0;
  double? _leftWidth;
  double? _dragStartLeftWidth;
  double? _dragStartGlobalX;

  @override
  Widget build(BuildContext context) {
    final leftFraction = widget._initialFractions.isNotEmpty
        ? widget._initialFractions.first
        : 0.23;
    final minLeft =
        widget._minSizes.isNotEmpty ? widget._minSizes.first : 100.0;
    final minRight = widget._minSizes.length > 1 ? widget._minSizes[1] : 200.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final total = constraints.maxWidth;
        final maximumLeft = total - minRight - _dividerWidth;
        final left = (_leftWidth ?? total * leftFraction).clamp(
          minLeft,
          maximumLeft,
        );
        final right = total - left - _dividerWidth;

        return Row(
          children: [
            SizedBox(width: left, child: widget._children.first),
            MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              child: GestureDetector(
                key: const ValueKey('details-resize-divider'),
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (details) {
                  _dragStartLeftWidth = left;
                  _dragStartGlobalX = details.globalPosition.dx;
                },
                onHorizontalDragUpdate: (details) {
                  final startWidth = _dragStartLeftWidth;
                  final startX = _dragStartGlobalX;
                  if (startWidth == null || startX == null) {
                    return;
                  }
                  setState(() {
                    _leftWidth =
                        (startWidth + (details.globalPosition.dx - startX))
                            .clamp(minLeft, maximumLeft);
                  });
                },
                onHorizontalDragEnd: (_) {
                  _dragStartLeftWidth = null;
                  _dragStartGlobalX = null;
                },
                child: Container(
                  width: _dividerWidth,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  alignment: Alignment.center,
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 24),
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
            ),
            SizedBox(width: right, child: widget._children[1]),
          ],
        );
      },
    );
  }
}
