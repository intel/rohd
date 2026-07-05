// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// regex_query.dart
// Regex/glob query implementation for hierarchy search.
//
// 2026 May
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd_hierarchy/src/hierarchy_query.dart';

/// Regex/glob query: each segment is a compiled regex, with `**` support
/// for crossing hierarchy boundaries.
///
/// ## Segment syntax
///
/// The query string is split on `/` into segments.  Each segment is
/// independently compiled as a case-insensitive [RegExp] anchored to the
/// full occurrence or signal name (`^…$`).  This means:
///
/// - **Plain names** match exactly: `Top/CPU/clk`.
/// - **Glob wildcards** are auto-converted before compilation:
///   - `*`  → `.*`  (match any characters)
///   - `?`  → `.`   (match one character)
///   - These compose naturally: `clk*` matches `clk`, `clk_gated`,
///     `clk_div2`, etc.
/// - **Full regex** is supported within each segment since the string
///   is passed to [RegExp]:
///   - `d[0-9]+`       — signals named `d0`, `d1`, `d12`, …
///   - `(clk|reset)`   — either `clk` or `reset`
///   - `data_[a-z]{2}` — `data_ab`, `data_xy`, …
///   - `.*mux.*`       — any name containing `mux`
///   - `ch[0-3]`       — `ch0`, `ch1`, `ch2`, `ch3`
///   - `r[0-9]{1,2}`   — `r0` through `r99`
/// - **`**`** (double-star, as its own segment) matches zero or more
///   hierarchy levels, allowing searches to cross boundaries:
///   - `Top/**/clk`        — `clk` at any depth below `Top`
///   - `**/d[0-9]+`        — any signal like `d0` anywhere
///   - `Top/**/ch*/data_*` — `data_*` signals inside `ch*` modules
///
/// ## Interaction between glob and regex
///
/// Glob conversion happens *before* regex compilation, so `*` and `?`
/// are always expanded.  If you need a literal `*` or `?` in the regex,
/// escape them: `\*`, `\?`.  All other regex metacharacters (`.`, `+`,
/// `|`, `(`, `)`, `[`, `]`, `{`, `}`, `^`, `$`) work as-is inside
/// each segment.
///
/// ## Examples
///
/// ```text
/// Query                     Matches
/// ─────────────────────────────────────────────────────────────
/// Top/CPU/clk               exact: Top → CPU → clk
/// Top/CPU/*                 all signals in Top/CPU
/// Top/*/clk                 clk one level below Top
/// Top/**/clk                clk at any depth below Top
/// Top/**/c.*                signals starting with 'c' anywhere
/// **/clk                    clk anywhere in hierarchy
/// **/(clk|reset)            clk or reset anywhere
/// Top/CPU/d[0-9]+           d0, d1, d12, … in Top/CPU
/// Top/**/ch[0-3]/data_*     data_* in ch0–ch3 at any depth
/// Top/mem_*/addr[0-9]*      addr0, addr1, … in mem_* modules
/// **/.*mux.*                any name containing 'mux' anywhere
/// ```
class RegexQuery extends HierarchyQuery {
  /// Compiled segments — either a regex or a glob-star sentinel.
  late final List<RegexSegment> segments;

  /// Create a regex query from [rawQuery].
  ///
  /// A standalone `*` is converted to `.*`, `?` to `.`.  The segment
  /// `**` matches zero or more hierarchy levels.
  RegexQuery(
    super.rawQuery, {
    super.target = SearchTarget.signals,
  }) : super(crossesBoundaries: false) {
    final parts = rawQuery
        .split('/')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    segments = parts.map((s) {
      if (s == '**') {
        return RegexSegment.globStar();
      }
      final pattern = _globToRegex(s);
      return RegexSegment(RegExp('^$pattern\$'));
    }).toList();
  }

  @override
  int get segmentCount => segments.length;

  @override
  Set<int> matchOccurrence(String occurrenceName, int stateIndex) {
    if (stateIndex >= segments.length) {
      return const {};
    }
    final seg = segments[stateIndex];
    final results = <int>{};
    if (seg.isGlobStar) {
      // ** matches zero levels (skip) …
      results
        ..addAll(matchOccurrence(occurrenceName, stateIndex + 1))
        // … or consumes this node and stays at ** (one-or-more levels).
        ..add(stateIndex);
    } else if (seg.regex!.hasMatch(occurrenceName)) {
      results.add(stateIndex + 1);
    }
    return results;
  }

  @override
  bool matchSignal(String signalName, int stateIndex) {
    // Walk past any trailing **'s to find the signal-matching segment.
    var i = stateIndex;
    while (i < segments.length && segments[i].isGlobStar) {
      i++;
    }
    if (i >= segments.length) {
      return true; // all consumed
    }
    // The segment at i must be the last real regex.
    if (!_allGlobStarAfter(i + 1)) {
      return false;
    }
    return segments[i].regex!.hasMatch(signalName);
  }

  @override
  bool isComplete(int stateIndex) =>
      stateIndex >= segments.length ||
      segments.skip(stateIndex).every((s) => s.isGlobStar);

  /// Check if all segments from [fromIdx] onward are glob-stars.
  bool _allGlobStarAfter(int fromIdx) =>
      segments.skip(fromIdx).every((s) => s.isGlobStar);

  /// Convert glob wildcards to regex equivalents.
  static String _globToRegex(String segment) {
    final buf = StringBuffer();
    for (var i = 0; i < segment.length; i++) {
      final c = segment[i];
      if (c == '*') {
        if (buf.toString().endsWith('.')) {
          buf.write('*');
        } else {
          buf.write('.*');
        }
      } else if (c == '?') {
        buf.write('.');
      } else {
        buf.write(c);
      }
    }
    return buf.toString();
  }
}

/// A compiled regex segment for [RegexQuery].
class RegexSegment {
  /// The compiled regex, or null for glob-star segments.
  final RegExp? regex;

  /// Whether this segment is a `**` glob-star.
  final bool isGlobStar;

  /// Create a regex segment.
  RegexSegment(this.regex) : isGlobStar = false;

  /// Create a glob-star segment (`**`).
  RegexSegment.globStar()
      : regex = null,
        isGlobStar = true;
}
