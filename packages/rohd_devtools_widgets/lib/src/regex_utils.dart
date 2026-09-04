// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause

// ignore_for_file: deprecated_member_use, unnecessary_ignore

/// Creates a regular-expression pattern with the requested matching options.
Pattern regExpPattern(
  String source, {
  bool multiLine = false,
  bool caseSensitive = true,
  bool unicode = false,
  bool dotAll = false,
}) =>
    RegExp(
      source,
      multiLine: multiLine,
      caseSensitive: caseSensitive,
      unicode: unicode,
      dotAll: dotAll,
    );

/// Whether [input] contains a match for [source].
bool regExpHasMatch(
  String source,
  String input, {
  bool multiLine = false,
  bool caseSensitive = true,
  bool unicode = false,
  bool dotAll = false,
}) =>
    regExpPattern(
      source,
      multiLine: multiLine,
      caseSensitive: caseSensitive,
      unicode: unicode,
      dotAll: dotAll,
    ).allMatches(input).isNotEmpty;

/// Returns the first match for [source] in [input], if one exists.
Match? regExpFirstMatch(
  String source,
  String input, {
  bool multiLine = false,
  bool caseSensitive = true,
  bool unicode = false,
  bool dotAll = false,
}) =>
    RegExp(
      source,
      multiLine: multiLine,
      caseSensitive: caseSensitive,
      unicode: unicode,
      dotAll: dotAll,
    ).firstMatch(input);

/// Returns all matches for [source] in [input], beginning at [start].
Iterable<Match> regExpAllMatches(
  String source,
  String input, {
  int start = 0,
  bool multiLine = false,
  bool caseSensitive = true,
  bool unicode = false,
  bool dotAll = false,
}) =>
    RegExp(
      source,
      multiLine: multiLine,
      caseSensitive: caseSensitive,
      unicode: unicode,
      dotAll: dotAll,
    ).allMatches(input, start);
