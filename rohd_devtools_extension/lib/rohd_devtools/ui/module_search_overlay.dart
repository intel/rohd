// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// module_search_overlay.dart

// Inline module search widget for finding modules in the hierarchy. Adapted
// from wire_search_overlay pattern, using rohd_hierarchy.searchOccurrences.
//
// 2026 February Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cubit/hierarchy_cubit.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart';

/// Inline module search widget that replaces the Search Tree text field.
///
/// Uses [HierarchyService.searchOccurrences] to find modules by name or
/// hierarchical path (e.g. "cpu/alu"). Results appear in a list below
/// the search field, exactly like the wire search overlay in the schematic
/// viewer but placed inline in the Module Tree panel.
///
/// Features:
/// - Real-time search as user types
/// - Arrow-key navigation through results
/// - Enter to select, Escape to clear results
/// - Shows module path and child count for each result
/// - Also fires [onSearchTermChanged] so the existing tree filter still works
class ModuleSearchField extends StatefulWidget {
  /// Hierarchy service for module search.
  final HierarchyService? hierarchy;

  /// Called on every text change so the tree filter (TreeSearchTermCubit)
  /// can be kept in sync.
  final ValueChanged<String>? onSearchTermChanged;

  /// Constructor for [ModuleSearchField].
  const ModuleSearchField({
    super.key,
    this.hierarchy,
    this.onSearchTermChanged,
  });

  @override
  State<ModuleSearchField> createState() => _ModuleSearchFieldState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<HierarchyService?>('hierarchy', hierarchy))
      ..add(
        ObjectFlagProperty<ValueChanged<String>?>.has(
          'onSearchTermChanged',
          onSearchTermChanged,
        ),
      );
  }
}

class _ModuleSearchFieldState extends State<ModuleSearchField> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();

  /// Shared search controller from rohd_hierarchy.
  late HierarchySearchController<OccurrenceSearchResult> _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = _buildController();
    _textController.addListener(_onSearchChanged);
  }

  @override
  void didUpdateWidget(covariant ModuleSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hierarchy != widget.hierarchy) {
      _ctrl = _buildController();
      _onSearchChanged();
    }
  }

  @override
  void dispose() {
    _textController
      ..removeListener(_onSearchChanged)
      ..dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  HierarchySearchController<OccurrenceSearchResult> _buildController() {
    final hierarchy = widget.hierarchy;
    if (hierarchy != null) {
      return HierarchySearchController.forOccurrences(hierarchy);
    }
    return HierarchySearchController(
      searchFn: (_) => <OccurrenceSearchResult>[],
      normalizeFn: HierarchySearchResult.normalizeQuery,
    );
  }

  // ─────────────── Search Logic ───────────────

  void _onSearchChanged() {
    final query = _textController.text;

    // Keep tree filter in sync
    widget.onSearchTermChanged?.call(query);

    setState(() {
      try {
        _ctrl.updateQuery(query);
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      } on Exception catch (_) {
        _ctrl.clear();
      }
    });
  }

  // ─────────────── Keyboard Navigation ───────────────

  void _selectNext() {
    setState(() {
      _ctrl.selectNext();
      _ensureSelectedVisible();
    });
  }

  void _selectPrevious() {
    setState(() {
      _ctrl.selectPrevious();
      _ensureSelectedVisible();
    });
  }

  void _selectCurrent() {
    final result = _ctrl.currentSelection;
    if (result == null) {
      return;
    }

    // Select the module via BLoC — same as clicking it in the tree.
    context.read<DevToolsHierarchyCubit>().selectModule(result.occurrence);

    // Clear the search field so the tree filter is removed and the
    // selected node becomes visible in the full tree.
    _textController.clear();
  }

  void _ensureSelectedVisible() {
    if (!_scrollController.hasClients) {
      return;
    }
    const itemHeight = 56.0;
    final offset = HierarchySearchController.scrollOffsetToReveal(
      selectedIndex: _ctrl.selectedIndex,
      itemHeight: itemHeight,
      viewportHeight: _scrollController.position.viewportDimension,
      currentOffset: _scrollController.offset,
    );
    if (offset != null) {
      _scrollController.jumpTo(offset);
    }
  }

  // ─────────────── Build ───────────────

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSearchField(context),
          if (_ctrl.hasResults) _buildResultsList(context),
        ],
      );

  Widget _buildSearchField(BuildContext context) => KeyboardListener(
        focusNode: FocusNode(),
        onKeyEvent: (event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
              _selectNext();
            } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
              _selectPrevious();
            } else if (event.logicalKey == LogicalKeyboardKey.enter) {
              _selectCurrent();
            } else if (event.logicalKey == LogicalKeyboardKey.escape) {
              _textController.clear();
            }
          }
        },
        child: TextField(
          controller: _textController,
          focusNode: _focusNode,
          decoration: InputDecoration(
            labelText: 'Search Modules',
            hintText: 'e.g. cpu/alu',
            prefixIcon: const Icon(Icons.search, size: 18),
            suffixText: _ctrl.hasResults ? _ctrl.counterText : null,
            isDense: true,
          ),
          onSubmitted: (_) => _selectCurrent(),
        ),
      );

  Widget _buildResultsList(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 260),
      child: ListView.builder(
        controller: _scrollController,
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: _ctrl.results.length,
        itemBuilder: (context, index) {
          final result = _ctrl.results[index];
          final isSelected = index == _ctrl.selectedIndex;
          final childCount = result.childCount;
          // Use the pre-computed display path from the enriched result
          final displayPath = result.displayPath;
          final childNames =
              result.occurrence.children.map((c) => c.name).take(5).join(', ');

          return InkWell(
            onTap: () {
              setState(() => _ctrl.selectAt(index));
              _selectCurrent();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: isSelected
                  ? theme.colorScheme.primary.withValues(alpha: 0.15)
                  : null,
              child: Row(
                children: [
                  Icon(
                    Icons.memory,
                    size: 16,
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          displayPath,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: isSelected
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (childCount > 0)
                          Text(
                            '$childCount '
                            '${childCount == 1 ? 'child' : 'children'}'
                            ': $childNames'
                            '${childCount > 5 ? ' \u2026' : ''}',
                            style: TextStyle(
                              fontSize: 10,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
