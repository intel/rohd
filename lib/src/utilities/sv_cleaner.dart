import 'package:meta/meta.dart';

@internal
abstract class SvCleaner {
  /// Removes all swizzle bit annotation comments from a generated SystemVerilog
  /// string for the purpose of helping test accurate SV.
  ///
  /// This function removes comments of the form `/* ... */` that contain bit
  /// range annotations (like `/* 7:0 */` or `/* 15 */`) and collapses the
  /// remaining content to the old style single-line format without spaces.
  static String removeSwizzleAnnotationComments(String sv) {
    // Single regex that handles all formatting cases
    return sv.replaceAllMapped(
        RegExp(r'(\{\s+|\s*/\*\s*\d+(?::\s*\d+)?\s*\*/\s*|\s+\})',
            multiLine: true), (match) {
      final matched = match.group(0)!;
      if (matched.contains('{')) return '{';
      if (matched.contains('}')) return '}';
      return ''; // Remove bit range annotations and their whitespace
    });
  }
}
