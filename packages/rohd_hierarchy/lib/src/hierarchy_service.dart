// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// hierarchy_service.dart
// Abstract interface for source-agnostic hardware hierarchy navigation.
//
// 2026 January
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd_hierarchy/src/hierarchy_models.dart';

/// Default path separator used when constructing paths from the tree.
const String _hierarchySeparator = '/';

/// A source-agnostic interface for navigating hardware hierarchy.
///
/// All search and navigation is driven by walking the [HierarchyNode] tree.
/// Nodes hold their [HierarchyNode.name], [HierarchyNode.children], and
/// [HierarchyNode.signals].  Full paths are constructed on the fly by
/// joining names with [_hierarchySeparator] — no pre-baked path strings
/// are needed for search.
///
/// Key methods:
/// - [searchSignals] — incremental signal search
/// - [searchModules] — find modules/instances by name
/// - [searchNodes] — find modules/instances, returning [HierarchyNode] objects
/// - [autocompletePaths] — incremental path completion
abstract mixin class HierarchyService {
  /// The root node for the hierarchy.
  HierarchyNode get root;

  /// Maximum number of results returned by search methods when no explicit
  /// `limit` is provided.
  static const int _defaultSearchLimit = 100;

  // ───────────── Address-based node/signal lookup ──────────────────

  /// Find a node by its [HierarchyAddress].  O(depth).
  HierarchyNode? nodeByAddress(HierarchyAddress address) =>
      address.path.fold<HierarchyNode?>(
          root,
          (node, idx) => node != null && idx >= 0 && idx < node.children.length
              ? node.children[idx]
              : null);

  /// Find a signal by its [HierarchyAddress].
  ///
  /// The parent portion of [address] navigates to the owning module;
  /// the last index selects the signal within that module.  O(depth).
  Signal? signalByAddress(HierarchyAddress address) {
    if (address.path.isEmpty) {
      return null;
    }
    final node = nodeByAddress(
        HierarchyAddress(address.path.sublist(0, address.path.length - 1)));
    final sigIdx = address.path.last;
    return (node != null && sigIdx >= 0 && sigIdx < node.signals.length)
        ? node.signals[sigIdx]
        : null;
  }

  // ───────────── Address ↔ pathname conversion ──────────────────

  /// Convert a pathname (e.g. `"Top/sub/clk"` or `"Top.sub.clk"`) to a
  /// [HierarchyAddress] by walking the tree.
  ///
  /// Delegates to [HierarchyAddress.tryFromPathname].
  HierarchyAddress? pathnameToAddress(String pathname) =>
      HierarchyAddress.tryFromPathname(pathname, root);

  /// Resolve a `/`-separated pathname to a [HierarchyNode].
  ///
  /// Convenience that composes [pathnameToAddress] and [nodeByAddress].
  /// Returns `null` when [pathname] does not match any node in the tree.
  HierarchyNode? nodeByPathname(String pathname) {
    final addr = pathnameToAddress(pathname);
    return addr == null ? null : nodeByAddress(addr);
  }

  /// Convert a [HierarchyAddress] back to a `/`-separated pathname by
  /// walking the tree using child indices.
  ///
  /// Returns `null` if the address doesn't resolve in the current tree
  /// (e.g. out-of-bounds indices).  O(depth).
  ///
  /// For signal addresses, the last index is resolved as a signal within
  /// the parent module.  For pure module addresses, every index is a child.
  ///
  /// Set [asSignal] to `true` when you know the address points to a signal
  /// (the last index is a signal offset rather than a child offset).
  /// When `false` (default), all indices are treated as child offsets.
  String? addressToPathname(HierarchyAddress address, {bool asSignal = false}) {
    if (address.path.isEmpty) {
      return root.name;
    }

    final indices = address.path;
    final moduleEndIdx = asSignal ? indices.length - 1 : indices.length;

    final walked = indices
        .sublist(0, moduleEndIdx)
        .fold<({List<String> parts, HierarchyNode node})?>((
      parts: [root.name],
      node: root,
    ), (cur, idx) {
      if (cur == null || idx < 0 || idx >= cur.node.children.length) {
        return null;
      }
      final child = cur.node.children[idx];
      return (parts: [...cur.parts, child.name], node: child);
    });
    if (walked == null) {
      return null;
    }

    if (asSignal && indices.isNotEmpty) {
      final sigIdx = indices.last;
      return (sigIdx >= 0 && sigIdx < walked.node.signals.length)
          ? [...walked.parts, walked.node.signals[sigIdx].name]
              .join(_hierarchySeparator)
          : null;
    }
    return walked.parts.join(_hierarchySeparator);
  }

  /// Resolve a waveform-style ID (dot-separated, e.g. `"dut.adder.clk"`)
  /// to a [HierarchyAddress].
  ///
  /// Normalises `.` → `/` then delegates to [pathnameToAddress].
  HierarchyAddress? waveformIdToAddress(String waveformId) =>
      pathnameToAddress(waveformId);

  // ───────────────────── Search / autocomplete ─────────────────────

  /// Find hierarchical signal paths matching [query].
  ///
  /// Walks the tree, matching name segments incrementally.  When the last
  /// query segment partially matches a signal name at or below the current
  /// node the full path is returned (e.g. `Top/block/signal`).
  ///
  /// Returns up to [limit] results.
  List<String> searchSignalPaths(String query, {int? limit}) {
    final effectiveLimit = limit ?? _defaultSearchLimit;
    if (query.trim().isEmpty) {
      return const [];
    }
    final parts = _splitPath(query);
    final results = <String>[];
    _searchSignalsRecursive(
        root, [root.name], parts, 0, results, effectiveLimit);
    return results;
  }

  /// Whether [query] contains glob or regex metacharacters that should
  /// trigger the regex search engine instead of the plain substring search.
  static bool hasRegexChars(String query) =>
      query.contains('*') ||
      query.contains('?') ||
      query.contains('[') ||
      query.contains('(') ||
      query.contains('|') ||
      query.contains('+');

  /// Check if a [node] or any of its descendants match [searchTerm].
  ///
  /// The search term is split on `/` or `.` into hierarchical segments.
  /// Each segment is matched case-insensitively via substring containment
  /// against node names at successive depths.
  ///
  /// Returns `true` if [searchTerm] is null/empty, or if the node (or a
  /// descendant) matches all segments in order.
  ///
  /// This is useful for tree-view filtering: show a node only when it or
  /// one of its descendants matches the user's query.
  static bool isNodeMatching(HierarchyNode node, String? searchTerm) {
    if (searchTerm == null || searchTerm.isEmpty) {
      return true;
    }

    final normalizedQuery = searchTerm.replaceAll('.', '/');
    final queryParts = normalizedQuery
        .toLowerCase()
        .split('/')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    return _isNodeMatchingRecursive(node, queryParts, 0);
  }

  static bool _isNodeMatchingRecursive(
      HierarchyNode node, List<String> queryParts, int queryIdx) {
    if (queryIdx >= queryParts.length) {
      return true;
    }

    final currentQueryPart = queryParts[queryIdx];
    final nodeName = node.name.toLowerCase();

    final matched = nodeName.contains(currentQueryPart);
    final nextQueryIdx = matched ? queryIdx + 1 : queryIdx;

    if (nextQueryIdx >= queryParts.length) {
      return true;
    }

    return node.children.any(
        (child) => _isNodeMatchingRecursive(child, queryParts, nextQueryIdx));
  }

  /// Search for signals and return enriched [SignalSearchResult] objects.
  ///
  /// Automatically dispatches to [searchSignalsRegex] when the query
  /// contains glob or regex metacharacters (`*`, `?`, `[`, `(`, `|`,
  /// `+`).  Otherwise uses [searchSignalPaths] for prefix-based matching.
  List<SignalSearchResult> searchSignals(String query, {int? limit}) {
    final effectiveLimit = limit ?? _defaultSearchLimit;
    if (hasRegexChars(query)) {
      final pattern = (query.startsWith('**/') || query.startsWith('*/'))
          ? query
          : '*/$query';
      return searchSignalsRegex(pattern, limit: effectiveLimit);
    }
    return _toSignalResults(searchSignalPaths(query, limit: effectiveLimit));
  }

  /// Find hierarchical module/node paths matching [query].
  ///
  /// Similar to [searchSignalPaths] but for modules/instances instead of
  /// signals. Walks the tree, matching name segments incrementally. When
  /// the query segments match module names at or below the current node
  /// the full path is returned (e.g. `Top/CPU/ALU`).
  ///
  /// Returns up to [limit] results.
  List<String> searchNodePaths(String query, {int? limit}) {
    final effectiveLimit = limit ?? _defaultSearchLimit;
    if (query.trim().isEmpty) {
      return const [];
    }
    final parts = _splitPath(query);
    final results = <String>[];
    _searchNodePathsRecursive(
        root, [root.name], parts, 0, results, effectiveLimit);
    return results;
  }

  /// Find hierarchy nodes whose path matches [query].
  ///
  /// Like [searchNodePaths] but returns the [HierarchyNode] objects
  /// themselves instead of path strings.
  List<HierarchyNode> searchNodes(String query, {int? limit}) {
    final effectiveLimit = limit ?? _defaultSearchLimit;
    if (query.trim().isEmpty) {
      return const [];
    }
    final parts = _splitPath(query);
    final results = <HierarchyNode>[];
    _searchNodesRecursive(root, parts, 0, results, effectiveLimit);
    return results;
  }

  /// Autocomplete suggestions for a partial hierarchical path.
  ///
  /// The partial path is split into segments.  Completed segments navigate
  /// down the tree; the final (possibly empty) segment is used as a prefix
  /// filter on children at that level.  Returns up to [limit] full paths
  /// (with `/` appended for nodes that have children).
  List<String> autocompletePaths(String partialPath, {int? limit}) {
    final effectiveLimit = limit ?? _defaultSearchLimit;
    final normalized = partialPath.replaceAll('.', _hierarchySeparator);
    final endsWithSep = normalized.endsWith(_hierarchySeparator);
    final parts = _splitPath(partialPath);

    // Navigate to the deepest complete segment.
    var current = root;
    final completedParts = <String>[root.name];

    final navParts = endsWithSep || parts.isEmpty
        ? parts
        : parts.sublist(0, parts.length - 1);
    for (final seg in navParts) {
      // If the segment matches the current node name, stay at this level
      // (handles the root name appearing as the first path segment).
      if (current.name.toLowerCase() == seg) {
        continue;
      }
      final child = current.children
          .where((c) => c.name.toLowerCase() == seg)
          .firstOrNull;
      if (child == null) {
        return const [];
      }
      current = child;
      completedParts.add(child.name);
    }

    // The trailing prefix to filter on (empty if path ends with separator).
    final prefix =
        (endsWithSep || parts.isEmpty) ? '' : parts.last.toLowerCase();

    final suggestions = <String>[];

    // When the prefix matches the current (root-level) node itself and we
    // haven't navigated past it, suggest the root path so that typing a
    // partial root name produces a completion.
    if (prefix.isNotEmpty &&
        completedParts.length == 1 &&
        current == root &&
        current.name.toLowerCase().startsWith(prefix)) {
      final rootPath = current.name;
      suggestions.add(current.children.isNotEmpty
          ? '$rootPath$_hierarchySeparator'
          : rootPath);
    }

    for (final child in current.children) {
      if (prefix.isEmpty || child.name.toLowerCase().startsWith(prefix)) {
        final path = [...completedParts, child.name].join(_hierarchySeparator);
        suggestions.add(
            child.children.isNotEmpty ? '$path$_hierarchySeparator' : path);
        if (suggestions.length >= effectiveLimit) {
          break;
        }
      }
    }
    return suggestions;
  }

  /// Search for modules/nodes and return enriched [ModuleSearchResult] objects.
  ///
  /// Automatically dispatches to [searchModulesRegex] when the query
  /// contains glob or regex metacharacters (`*`, `?`, `[`, `(`, `|`,
  /// `+`).  Otherwise uses [searchNodePaths] for prefix-based matching.
  List<ModuleSearchResult> searchModules(String query, {int? limit}) {
    final effectiveLimit = limit ?? _defaultSearchLimit;
    if (hasRegexChars(query)) {
      final pattern = (query.startsWith('**/') || query.startsWith('*/'))
          ? query
          : '**/$query';
      return searchModulesRegex(pattern, limit: effectiveLimit);
    }
    return _toModuleResults(searchNodePaths(query, limit: effectiveLimit));
  }

  // ───────────────── Regex search ─────────────────

  /// Search for signals whose hierarchical path matches a regex [pattern].
  ///
  /// The pattern is split on `/` or `.` into segments.  Each segment is
  /// compiled as a case-insensitive [RegExp] and matched against the
  /// corresponding depth in the hierarchy tree.  Special segments:
  ///
  /// - `**` — matches zero or more hierarchy levels (glob-star).  Use this
  ///   to search across hierarchy boundaries, e.g. `Top/**/clk` finds
  ///   `Top/CPU/ALU/clk`, `Top/Memory/clk`, etc.
  /// - Any other string is compiled as a regex anchored to the full name
  ///   (`^…$`).  Plain names therefore match exactly and regex meta-
  ///   characters like `.*`, `[0-9]+`, etc. work as expected.
  ///
  /// Returns up to [limit] full hierarchical signal paths.
  ///
  /// Examples:
  /// ```text
  /// 'Top/CPU/clk'        — exact match at each level
  /// 'Top/CPU/.*'         — all signals in Top/CPU
  /// 'Top/.*/clk'         — clk signal one level below Top
  /// 'Top/**/clk'         — clk signal at any depth below Top
  /// 'Top/**/c.*'         — signals starting with 'c' at any depth
  /// '**/(clk|reset)'     — clk or reset anywhere in hierarchy
  /// 'Top/CPU/d[0-9]+'    — signals like d0, d1, d12 in Top/CPU
  /// ```
  List<String> searchSignalPathsRegex(String pattern, {int? limit}) {
    final effectiveLimit = limit ?? _defaultSearchLimit;
    if (pattern.trim().isEmpty) {
      return const [];
    }
    final segments = _splitRegexPattern(pattern);
    final compiled = _compileSegments(segments);
    final results = <String>[];
    _searchSignalsRegex(
        root, [root.name], compiled, 0, results, effectiveLimit);
    return results;
  }

  /// Search for signals by regex pattern and return enriched results.
  List<SignalSearchResult> searchSignalsRegex(String pattern, {int? limit}) =>
      _toSignalResults(searchSignalPathsRegex(pattern, limit: limit));

  /// Search for module/node paths matching a regex [pattern].
  ///
  /// Same segment syntax as [searchSignalPathsRegex] but matches module
  /// nodes instead of signals.
  ///
  /// Returns up to [limit] full hierarchical module paths.
  List<String> searchNodePathsRegex(String pattern, {int? limit}) {
    final effectiveLimit = limit ?? _defaultSearchLimit;
    if (pattern.trim().isEmpty) {
      return const [];
    }
    final segments = _splitRegexPattern(pattern);
    final compiled = _compileSegments(segments);
    final results = <String>[];
    _searchNodesRegex(root, [root.name], compiled, 0, results, effectiveLimit);
    return results;
  }

  /// Search for modules by regex pattern and return enriched results.
  List<ModuleSearchResult> searchModulesRegex(String pattern, {int? limit}) =>
      _toModuleResults(searchNodePathsRegex(pattern, limit: limit));

  // ─────────────────── Utility helpers ───────────────────

  /// Returns the longest common prefix shared by all [paths].
  ///
  /// Comparison is case-insensitive.  Returns `null` when [paths] is empty
  /// or no common prefix exists.
  static String? longestCommonPrefix(List<String> paths) {
    if (paths.isEmpty) {
      return null;
    }
    final prefix = paths.skip(1).fold<String?>(paths.first, (pre, s) {
      if (pre == null || pre.isEmpty) {
        return null;
      }
      final end = pre.length < s.length ? pre.length : s.length;
      final j = Iterable<int>.generate(end)
          .takeWhile((i) => pre[i].toLowerCase() == s[i].toLowerCase())
          .length;
      return j > 0 ? pre.substring(0, j) : null;
    });
    return prefix;
  }

  // ─────────────────── Private helpers ───────────────────

  /// Split a query or path on `/` or `.` into non-empty lower-case segments.
  static List<String> _splitPath(String input) => input
      .replaceAll('.', _hierarchySeparator)
      .toLowerCase()
      .split(_hierarchySeparator)
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  /// Split a path on `/` or `.` into non-empty segments, preserving case.
  ///
  /// Use this when the result is for display or building [SignalSearchResult]
  /// path parts — not for matching.
  static List<String> _splitPathPreserveCase(String input) => input
      .replaceAll('.', _hierarchySeparator)
      .split(_hierarchySeparator)
      .where((s) => s.isNotEmpty)
      .toList();

  /// Enrich signal paths into [SignalSearchResult] objects.
  List<SignalSearchResult> _toSignalResults(List<String> paths) =>
      paths.map((fullPath) {
        final addr = HierarchyAddress.tryFromPathname(fullPath, root);
        return SignalSearchResult(
          signalId: fullPath,
          path: _splitPathPreserveCase(fullPath),
          signal: addr != null ? signalByAddress(addr) : null,
        );
      }).toList();

  /// Enrich module paths into [ModuleSearchResult] objects.
  List<ModuleSearchResult> _toModuleResults(List<String> paths) =>
      paths.map((fullPath) {
        final addr = HierarchyAddress.tryFromPathname(fullPath, root);
        return ModuleSearchResult(
          moduleId: fullPath,
          path: _splitPathPreserveCase(fullPath),
          node: (addr != null ? nodeByAddress(addr) : null) ?? root,
        );
      }).toList();

  /// Recursively search for signals matching query parts.
  ///
  /// Walks the tree maintaining the path of names.  When the accumulated
  /// match depth reaches the query length, checks signals at that node.
  /// Partial last-segment matching also checks signals at partially-matched
  /// nodes.
  ///
  /// Uses [HierarchyNode.children] and [HierarchyNode.signals] directly.
  void _searchSignalsRecursive(
    HierarchyNode node,
    List<String> pathSoFar,
    List<String> queryParts,
    int qIdx,
    List<String> results,
    int limit,
  ) {
    if (results.length >= limit) {
      return;
    }

    // Try matching current node name against current query part
    final nodeName = node.name.toLowerCase();
    final currentQuery = qIdx < queryParts.length ? queryParts[qIdx] : null;
    final matched = currentQuery != null && nodeName.startsWith(currentQuery);
    final nextIdx = matched ? qIdx + 1 : qIdx;

    // Determine how many query parts remain after any node-name match.
    final remaining = queryParts.length - nextIdx;

    // If 0 or 1 query parts remain, search signals at this node.
    if (remaining <= 1) {
      // When the current node consumed the last segment (remaining==0,
      // matched==true), reuse that segment as the signal filter so that
      // e.g. "a" doesn't return every signal under a module named "alu".
      // When remaining==0 because we're recursing into a subtree where
      // a parent already consumed all segments, use empty (return all).
      final signalQuery = remaining == 1
          ? queryParts[nextIdx]
          : (matched && qIdx < queryParts.length ? queryParts[qIdx] : '');
      for (final signal in node.signals) {
        if (results.length >= limit) {
          return;
        }
        if (signalQuery.isEmpty ||
            signal.name.toLowerCase().startsWith(signalQuery)) {
          final fullPath =
              [...pathSoFar, signal.name].join(_hierarchySeparator);
          results.add(fullPath);
        }
      }
    }

    // Recurse into children
    for (final child in node.children) {
      if (results.length >= limit) {
        return;
      }
      _searchSignalsRecursive(
        child,
        [...pathSoFar, child.name],
        queryParts,
        nextIdx,
        results,
        limit,
      );
    }
  }

  /// Recursively search for module nodes matching query parts.
  ///
  /// Similar to [_searchSignalsRecursive] but matches module nodes instead
  /// of signals. Walks the tree maintaining the path of names. When the
  /// query segments match module names, adds them to results.
  void _searchNodePathsRecursive(
    HierarchyNode node,
    List<String> pathSoFar,
    List<String> queryParts,
    int qIdx,
    List<String> results,
    int limit,
  ) {
    if (results.length >= limit) {
      return;
    }

    // Try matching current node name against current query part
    final nodeName = node.name.toLowerCase();
    final currentQuery = qIdx < queryParts.length ? queryParts[qIdx] : null;
    final matched = currentQuery != null && nodeName.contains(currentQuery);
    final nextIdx = matched ? qIdx + 1 : qIdx;

    // If all query parts are matched, this node is a result
    if (nextIdx >= queryParts.length) {
      final fullPath = pathSoFar.join(_hierarchySeparator);
      results.add(fullPath);
      if (results.length >= limit) {
        return;
      }
    }

    // Recurse into children
    for (final child in node.children) {
      if (results.length >= limit) {
        return;
      }
      _searchNodePathsRecursive(
        child,
        [...pathSoFar, child.name],
        queryParts,
        nextIdx,
        results,
        limit,
      );
    }
  }

  /// Recursively search for nodes matching query parts, returning the nodes.
  void _searchNodesRecursive(HierarchyNode node, List<String> queryParts,
      int qIdx, List<HierarchyNode> results, int limit) {
    if (results.length >= limit) {
      return;
    }

    final matched = qIdx < queryParts.length &&
        node.name.toLowerCase().contains(queryParts[qIdx]);
    final nextIdx = matched ? qIdx + 1 : qIdx;

    if (nextIdx >= queryParts.length) {
      results.add(node);
      if (results.length >= limit) {
        return;
      }
    }

    for (final child in node.children) {
      _searchNodesRecursive(child, queryParts, nextIdx, results, limit);
      if (results.length >= limit) {
        return;
      }
    }
  }

  // ─────────────── Regex search helpers ───────────────

  /// A compiled regex segment.  `isGlobStar` indicates a `**` segment that
  /// matches zero or more hierarchy levels.
  static const _globStarSentinel = '**';

  /// Split `pattern` into segments on `/` only.
  ///
  /// Unlike [_splitPath] (which also splits on `.`), regex patterns use only
  /// `/` as the hierarchy separator because `.` has meaning inside regular
  /// expressions (e.g. `.*`, `a.b`).
  List<String> _splitRegexPattern(String input) =>
      input.split('/').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  /// Convert glob-style `*` and `?` wildcards to regex equivalents.
  ///
  /// A standalone `*` (not preceded/followed by another regex metachar)
  /// becomes `.*` (match anything).  `?` becomes `.` (match one char).
  /// This lets users write natural patterns like `*m`, `clk*`, `*data*`
  /// without needing to know regex syntax.
  String _globToRegex(String segment) {
    final buf = StringBuffer();
    for (var i = 0; i < segment.length; i++) {
      final c = segment[i];
      if (c == '*') {
        // If already preceded by `.` (i.e. user wrote `.*`), skip conversion.
        if (buf.toString().endsWith('.')) {
          buf.write('*');
        } else {
          buf.write('.*');
        }
      } else if (c == '?') {
        // If already preceded by a valid quantifier target, keep literal `?`.
        // Otherwise treat as single-char wildcard `.`.
        if (i > 0 && !'.?*+'.contains(segment[i - 1])) {
          buf.write('?');
        } else {
          buf.write('.');
        }
      } else {
        buf.write(c);
      }
    }
    return buf.toString();
  }

  /// Compile string segments into [_RegexSegment] list.
  ///
  /// Each segment is first run through [_globToRegex] so that glob-style
  /// wildcards (`*`, `?`) work alongside full regex syntax.
  List<_RegexSegment> _compileSegments(List<String> segments) =>
      segments.map((s) {
        if (s == _globStarSentinel) {
          return _RegexSegment.globStar();
        }
        final pattern = _globToRegex(s);
        // Anchor the regex to match the full name.
        return _RegexSegment(RegExp('^$pattern\$', caseSensitive: false));
      }).toList();

  /// Recursive signal search driven by compiled regex segments.
  ///
  /// [segIdx] is the index into [segments] that we are currently trying to
  /// match at this tree depth.
  void _searchSignalsRegex(
    HierarchyNode node,
    List<String> pathSoFar,
    List<_RegexSegment> segments,
    int segIdx,
    List<String> results,
    int limit,
  ) {
    if (results.length >= limit) {
      return;
    }

    // Determine how many segments remain after consuming the current node.
    final consumed = _matchNode(node.name, segments, segIdx);

    for (final nextIdx in consumed) {
      if (results.length >= limit) {
        return;
      }

      // Try to match signals at this node.
      // Find all indices reachable from nextIdx by skipping glob-stars
      // where a signal-level regex (or end-of-pattern) can be applied.
      for (final sigIdx in _signalReachableIndices(segments, nextIdx)) {
        if (results.length >= limit) {
          return;
        }
        if (sigIdx >= segments.length) {
          // All segments consumed: collect all signals at this node.
          for (final signal in node.signals) {
            if (results.length >= limit) {
              return;
            }
            results.add([...pathSoFar, signal.name].join(_hierarchySeparator));
          }
        } else {
          // sigIdx points to a non-** regex that should match signal names.
          final sigSeg = segments[sigIdx];
          // Only use as signal-level match if this is the last non-** segment
          // (possibly followed by more **'s that can match zero levels).
          if (_allGlobStarAfter(segments, sigIdx + 1)) {
            for (final signal in node.signals) {
              if (results.length >= limit) {
                return;
              }
              if (sigSeg.regex!.hasMatch(signal.name)) {
                results
                    .add([...pathSoFar, signal.name].join(_hierarchySeparator));
              }
            }
          }
        }
      }

      // Recurse into children.
      for (final child in node.children) {
        if (results.length >= limit) {
          return;
        }
        _searchSignalsRegex(
          child,
          [...pathSoFar, child.name],
          segments,
          nextIdx,
          results,
          limit,
        );
      }
    }
  }

  /// Recursive module/node search driven by compiled regex segments.
  void _searchNodesRegex(
    HierarchyNode node,
    List<String> pathSoFar,
    List<_RegexSegment> segments,
    int segIdx,
    List<String> results,
    int limit,
  ) {
    if (results.length >= limit) {
      return;
    }

    final consumed = _matchNode(node.name, segments, segIdx);

    for (final nextIdx in consumed) {
      if (results.length >= limit) {
        return;
      }

      // All segments consumed (or only trailing **'s remain) → match.
      if (_allGlobStarAfter(segments, nextIdx)) {
        results.add(pathSoFar.join(_hierarchySeparator));
        if (results.length >= limit) {
          return;
        }
      }

      // Recurse into children.
      for (final child in node.children) {
        if (results.length >= limit) {
          return;
        }
        _searchNodesRegex(
          child,
          [...pathSoFar, child.name],
          segments,
          nextIdx,
          results,
          limit,
        );
      }
    }
  }

  /// Try to match [nodeName] against the segment at [segIdx].
  ///
  /// Returns a set of possible next-segment indices (branching is needed
  /// because `**` can consume zero or more levels).
  Set<int> _matchNode(
      String nodeName, List<_RegexSegment> segments, int segIdx) {
    final results = <int>{};
    if (segIdx >= segments.length) {
      // No more segments to match — nothing to advance to.
      return results;
    }

    final seg = segments[segIdx];

    if (seg.isGlobStar) {
      // ** matches zero levels (skip the **) …
      results
        ..addAll(_matchNode(nodeName, segments, segIdx + 1))
        // … or consumes this node and stays at ** (one-or-more levels).
        ..add(segIdx);
    } else if (seg.regex!.hasMatch(nodeName)) {
      results.add(segIdx + 1);
    }
    // If the segment doesn't match at all, return empty → prune this branch.
    return results;
  }

  /// Returns indices in [segments] reachable from [fromIdx] by skipping
  /// consecutive `**` glob-star segments.  Always includes [fromIdx] itself
  /// if it is in range (or == segments.length, meaning "past the end").
  Set<int> _signalReachableIndices(List<_RegexSegment> segments, int fromIdx) {
    final result = <int>{};
    var i = fromIdx;
    // Walk forward: each time we see a **, we can skip it (zero levels).
    while (i < segments.length) {
      if (segments[i].isGlobStar) {
        // ** can match zero levels → skip and also record i (stay at **).
        result.add(i + 1); // skip the **
        i++;
      } else {
        result.add(i);
        break; // stop at first non-** segment
      }
    }
    // If we walked past the end, record that too.
    if (i >= segments.length) {
      result.add(segments.length);
    }
    return result;
  }

  /// Returns true if all segments from [fromIdx] onward are glob-stars
  /// (or if [fromIdx] >= length, i.e. no more segments).
  bool _allGlobStarAfter(List<_RegexSegment> segments, int fromIdx) =>
      segments.skip(fromIdx).every((s) => s.isGlobStar);
}

/// Internal representation of a compiled regex segment.
class _RegexSegment {
  final RegExp? regex;
  final bool isGlobStar;

  _RegexSegment(this.regex) : isGlobStar = false;
  _RegexSegment.globStar()
      : regex = null,
        isGlobStar = true;
}
