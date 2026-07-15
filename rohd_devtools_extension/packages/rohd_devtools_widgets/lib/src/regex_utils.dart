// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause

// ignore_for_file: deprecated_member_use, unnecessary_ignore

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
