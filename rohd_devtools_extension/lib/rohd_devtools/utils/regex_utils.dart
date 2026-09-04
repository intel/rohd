// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause

// RegExp remains the compatibility implementation until Pattern gains parity.
// ignore_for_file: deprecated_member_use, unnecessary_ignore

/// Creates a regular-expression [Pattern] while keeping direct RegExp
/// construction isolated from call sites.
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

/// Returns whether [input] matches the regular expression [source].
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

/// Returns the first regular-expression match for [source] in [input].
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

/// Returns all regular-expression matches for [source] in [input].
Iterable<Match> regExpAllMatches(
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
    ).allMatches(input);
