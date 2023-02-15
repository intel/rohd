/// Copyright (C) 2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// vcd_parser.dart
/// Utility for parsing VCD files for tests
///
/// 2023 January 5
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:rohd/rohd.dart';

/// State of VCD parsing
enum _VcdParseState { findSig, findDumpVars, findValue }

/// A parser for VCD files for testing purposes.
abstract class VcdParser {
  /// Checks that the contents of a VCD file ([vcdContents]) have [value] on
  /// [signalName] at time [timestamp].
  ///
  /// This function is basic and only works on flat, single modules, or at least
  /// cases where only one signal is named [signalName] across all scopes.
  static bool confirmValue(
      String vcdContents, String signalName, int timestamp, LogicValue value) {
    final lines = vcdContents.split('\n');

    String? sigName;
    int? width;
    var currentTime = 0;
    LogicValue? currentValue;

    var state = _VcdParseState.findSig;

    final sigNameRegexp = RegExp(
        r'\s*\$var\s(wire|reg)\s(\d+)\s(\S*)\s(\S*)\s+(\[\d+\:\d+\])?\s*\$end');
    for (final line in lines) {
      if (state == _VcdParseState.findSig) {
        if (sigNameRegexp.hasMatch(line)) {
          final match = sigNameRegexp.firstMatch(line)!;
          final w = int.parse(match.group(2)!);
          final sName = match.group(3)!;
          final lName = match.group(4)!;

          if (lName == signalName) {
            sigName = sName;
            width = w;
            state = _VcdParseState.findDumpVars;
          }
        }
      } else if (state == _VcdParseState.findDumpVars) {
        if (line.contains(r'$dumpvars')) {
          state = _VcdParseState.findValue;
        }
      } else if (state == _VcdParseState.findValue) {
        if (line.startsWith('#')) {
          currentTime = int.parse(line.substring(1));
          if (currentTime > timestamp) {
            return currentValue == value;
          }
        } else if (line.endsWith(sigName!)) {
          if (width == 1) {
            // ex: zs1
            currentValue = LogicValue.ofString(line[0]);
          } else {
            // ex: bzzzzzzzz s2
            currentValue = LogicValue.ofString(line.split(' ')[0].substring(1));
          }

          currentValue = currentValue.zeroExtend(width!);
        }
      }
    }
    return currentValue == value;
  }
}
