// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// hierarchy_search_controller.dart
// Pure Dart controller for hierarchy search list navigation.
//
// 2026 February
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd_hierarchy/rohd_hierarchy.dart';

/// Pure Dart controller for hierarchy search list navigation.
///
/// Manages search results and keyboard-style list selection without
/// any Flutter dependency.  Widgets call controller methods, then
/// refresh their own UI (e.g. `setState`).
///
/// Generic over the result type [R] — typically [SignalSearchResult]
/// or [ModuleSearchResult].
///
/// ```dart
/// // In a Flutter widget:
/// final controller = HierarchySearchController.forSignals(hierarchy);
///
/// void _onSearchChanged() {
///   controller.updateQuery(_textController.text);
///   setState(() {});
/// }
/// ```
class HierarchySearchController<R> {
  /// The search function that produces results from a normalised query.
  final List<R> Function(String normalizedQuery) _searchFn;

  /// Normalises a raw user query (e.g. replaces `.` with `/`).
  final String Function(String rawQuery) _normalizeFn;

  List<R> _results = [];
  int _selectedIndex = 0;

  /// Create a controller with custom search and normalise functions.
  HierarchySearchController({
    required List<R> Function(String normalizedQuery) searchFn,
    required String Function(String rawQuery) normalizeFn,
  })  : _searchFn = searchFn,
        _normalizeFn = normalizeFn;

  /// Create a controller for **signal** search on the given
  /// [HierarchyService].
  ///
  /// When the query contains glob/regex metacharacters, normalisation
  /// is skipped so that `.` keeps its regex meaning (use `/` as the
  /// hierarchy separator in regex patterns).
  factory HierarchySearchController.forSignals(
    HierarchyService hierarchy,
  ) =>
      HierarchySearchController<R>(
        searchFn: (q) => hierarchy.searchSignals(q) as List<R>,
        normalizeFn: (q) => HierarchyService.hasRegexChars(q)
            ? q
            : SignalSearchResult.normalizeQuery(q),
      );

  /// Create a controller for **module** search on the given
  /// [HierarchyService].
  ///
  /// When the query contains glob/regex metacharacters, normalisation
  /// is skipped so that `.` keeps its regex meaning (use `/` as the
  /// hierarchy separator in regex patterns).
  factory HierarchySearchController.forModules(
    HierarchyService hierarchy,
  ) =>
      HierarchySearchController<R>(
        searchFn: (q) => hierarchy.searchModules(q) as List<R>,
        normalizeFn: (q) => HierarchyService.hasRegexChars(q)
            ? q
            : ModuleSearchResult.normalizeQuery(q),
      );

  // ─────────────── State accessors ───────────────

  /// The current search results.
  List<R> get results => _results;

  /// Index of the currently highlighted result.
  int get selectedIndex => _selectedIndex;

  /// Whether there are any results.
  bool get hasResults => _results.isNotEmpty;

  /// A human-readable counter string, e.g. `"3/12"`, or empty when
  /// there are no results.
  String get counterText =>
      hasResults ? '${_selectedIndex + 1}/${_results.length}' : '';

  /// The currently selected result, or `null` if the list is empty.
  R? get currentSelection => _results.isEmpty ? null : _results[_selectedIndex];

  // ─────────────── Mutations ───────────────

  /// Update search results for [rawQuery].
  ///
  /// Normalises the query, runs the search function, and resets the
  /// selection to the first result.  The caller should rebuild its UI
  /// after calling this.
  void updateQuery(String rawQuery) {
    if (rawQuery.isEmpty) {
      _results = [];
      _selectedIndex = 0;
      return;
    }
    final normalized = _normalizeFn(rawQuery);
    _results = _searchFn(normalized);
    _selectedIndex = 0;
  }

  /// Move selection to the next result, wrapping around.
  void selectNext() {
    if (_results.isEmpty) {
      return;
    }
    _selectedIndex = (_selectedIndex + 1) % _results.length;
  }

  /// Move selection to the previous result, wrapping around.
  void selectPrevious() {
    if (_results.isEmpty) {
      return;
    }
    _selectedIndex = (_selectedIndex - 1 + _results.length) % _results.length;
  }

  /// Move selection to a specific [index].
  ///
  /// Clamps to valid range.  Useful for tap-to-select in a list view.
  void selectAt(int index) {
    if (_results.isEmpty) {
      return;
    }
    _selectedIndex = index.clamp(0, _results.length - 1);
  }

  /// Clear all results and reset the selection index.
  void clear() {
    _results = [];
    _selectedIndex = 0;
  }

  // ─────────────── Tab-completion ───────────────

  /// Compute the tab-completion expansion for [currentQuery].
  ///
  /// Finds the longest common prefix of all current result display paths
  /// and returns it if it is strictly longer than [currentQuery].
  /// Returns `null` when there is nothing to expand.
  ///
  /// [displayPath] extracts the comparable path string from each result.
  /// The default implementation handles [SignalSearchResult] and
  /// [ModuleSearchResult] automatically; pass a custom extractor for
  /// other result types.
  String? tabComplete(
    String currentQuery, {
    String Function(R result)? displayPath,
  }) {
    if (_results.isEmpty) {
      return null;
    }

    final extractor = displayPath ?? _defaultDisplayPath;
    final paths = _results.map(extractor).toList();
    final prefix = HierarchyService.longestCommonPrefix(paths);
    if (prefix == null) {
      return null;
    }

    // Normalise the query the same way UpdateQuery does so lengths are
    // comparable (e.g. dots → slashes).
    final normalizedQuery = _normalizeFn(currentQuery);
    if (prefix.length <= normalizedQuery.length) {
      return null;
    }
    return prefix;
  }

  /// Default display-path extractor for the well-known result types.
  static String _defaultDisplayPath<T>(T result) {
    if (result is SignalSearchResult) {
      return result.displayPath;
    }
    if (result is ModuleSearchResult) {
      return result.displayPath;
    }
    return result.toString();
  }

  // ─────────────── Scroll helper ───────────────

  /// Compute the scroll offset needed to reveal the selected item in a
  /// fixed-height list.
  ///
  /// Returns `null` if the item is already visible.  The caller should
  /// call `scrollController.jumpTo(offset)` with the returned value.
  ///
  /// This is a pure calculation with no Flutter dependency.
  static double? scrollOffsetToReveal({
    required int selectedIndex,
    required double itemHeight,
    required double viewportHeight,
    required double currentOffset,
  }) {
    final target = selectedIndex * itemHeight;
    if (target < currentOffset) {
      return target;
    }
    if (target + itemHeight > currentOffset + viewportHeight) {
      return target + itemHeight - viewportHeight;
    }
    return null;
  }
}
