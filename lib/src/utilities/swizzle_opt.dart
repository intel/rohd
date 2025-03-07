
// ignore: public_member_api_docs
class SystemVerilogSwizzleOptimizer {
  // Method to optimize assignments in SystemVerilog code
  // ignore: public_member_api_docs
  static String optimizeAssignments(String svCode) {
    // Split the code into lines for processing
    List<String> lines = svCode.split('\n');
    List<String> optimizedLines = [];

    // A map to store variable widths
    Map<String, int> variableWidths = {};

    for (var line in lines) {
      // Check for logic declarations to capture variable widths
      var declarationMatch = RegExp(r'logic\s*\[(\d+):(\d+)\]\s*(\w+);').firstMatch(line);
      if (declarationMatch != null) {
        int upperBound = int.parse(declarationMatch.group(1)!);
        int lowerBound = int.parse(declarationMatch.group(2)!);
        String varName = declarationMatch.group(3)!;
        int width = (upperBound - lowerBound).abs() + 1;
        variableWidths[varName] = width;
      }

      // Check if the line contains a swizzle conversion
      if (line.contains('= {') && line.contains('};')) {
        // Perform optimization logic here
        String optimizedLine = optimizeLine(line, variableWidths);
        optimizedLines.add(optimizedLine);
      } else {
        optimizedLines.add(line);
      }
    }

    // Join the optimized lines back into a single string
    return optimizedLines.join('\n');
  }

  // Method to optimize a single line of SystemVerilog code
  static String optimizeLine(String line, Map<String, int> variableWidths) {
    // Example logic to identify and optimize swizzle conversions
    return line.replaceAllMapped(
        RegExp(r'(\w+)\s*=\s*{\s*(\w+)\s*};'), (match) {
      String lhs = match.group(1)!;
      String rhs = match.group(2)!;

      // Check if the widths match for direct assignment
      if (variableWidths.containsKey(lhs) &&
          variableWidths.containsKey(rhs) &&
          variableWidths[lhs] == variableWidths[rhs]) {
        // Transform swizzle conversion to direct assignment
        return '$lhs = $rhs;';
      }

      // Return the original line if widths do not match
      return line;
    });
  }
}