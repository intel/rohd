// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// sv_cleaner.dart
// Internal helper utilities for changing generated SV for testing purposes
// only.  This should NOT be used for anything else.
//
// 2025 November 5
// Author: Max Korbel <max.korbel@intel.com>

import 'package:meta/meta.dart';

@internal
abstract class SvCleaner {
  /// Removes all swizzle bit annotation comments from a generated SystemVerilog
  /// string for the purpose of helping test accurate SV.
  ///
  /// This function removes comments of the form `/* ... */` that contain bit
  /// range annotations (like `/* 7:0 */` or `/* 15 */`) and collapses the
  /// remaining content to the old style single-line format without spaces.
  ///
  /// This is specifically for tests that compare generated SV strings where
  /// bit range annotations are not relevant to the test and would only add
  /// noise.
  @internal
  static String removeSwizzleAnnotationComments(String sv) =>
      // Single regex that handles all formatting cases
      sv.replaceAllMapped(
          RegExp(r'(\{\s+|\s*/\*\s*\d+(?::\s*\d+)?\s*\*/\s*|\s+\})',
              multiLine: true), (match) {
        final matched = match.group(0)!;
        if (matched.contains('{')) {
          return '{';
        }
        if (matched.contains('}')) {
          return '}';
        }
        return ''; // Remove bit range annotations and their whitespace
      });
}
