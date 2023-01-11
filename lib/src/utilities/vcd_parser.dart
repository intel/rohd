import 'package:rohd/rohd.dart';

/// State of VCD parsing
enum _VCDParseState { findSig, findDumpVars, findValue }

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

    var state = _VCDParseState.findSig;

    final sigNameRegexp = RegExp(r'\s*\$var\swire\s(\d+)\s(\S*)\s(\S*)\s\$end');
    for (final line in lines) {
      if (state == _VCDParseState.findSig) {
        if (sigNameRegexp.hasMatch(line)) {
          final match = sigNameRegexp.firstMatch(line)!;
          final w = int.parse(match.group(1)!);
          final sName = match.group(2)!;
          final lName = match.group(3)!;

          if (lName == signalName) {
            sigName = sName;
            width = w;
            state = _VCDParseState.findDumpVars;
          }
        }
      } else if (state == _VCDParseState.findDumpVars) {
        if (line.contains(r'$dumpvars')) {
          state = _VCDParseState.findValue;
        }
      } else if (state == _VCDParseState.findValue) {
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
        }
      }
    }
    return currentValue == value;
  }
}
