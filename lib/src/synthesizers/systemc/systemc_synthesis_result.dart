// Copyright (C) 2021-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// systemc_synthesis_result.dart
// Definition for SystemCSynthesisResult
//
// 2026 May
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:collection/collection.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/modules/conditionals/always.dart';
import 'package:rohd/src/synthesizers/systemc/systemc_synth_module_definition.dart';
import 'package:rohd/src/synthesizers/systemc/systemc_synth_sub_module_instantiation.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';

/// A [SynthesisResult] representing a conversion of a [Module] to SystemC.
class SystemCSynthesisResult extends SynthesisResult {
  /// A cached copy of the generated ports.
  late final String _portsString;

  /// A cached copy of the generated module body (used for matching).
  late final String _moduleBodyString;

  /// The main [SynthModuleDefinition] for this.
  final SynthModuleDefinition _synthModuleDefinition;

  @override
  List<Module> get supportingModules =>
      _synthModuleDefinition.supportingModules;

  // Cached sections for final assembly
  late final String _internalSigs;
  late final String _subMembers;
  late final String _ctorBody;
  late final String _methodBodies;

  /// Creates a new [SystemCSynthesisResult] for the given [module].
  SystemCSynthesisResult(super.module, super.getInstanceTypeOfModule)
      : _synthModuleDefinition = SystemCSynthModuleDefinition(module) {
    _findClockResetSignals();
    _portsString = _systemCPorts();
    _buildModuleBody(getInstanceTypeOfModule);
    _moduleBodyString = '$_ctorBody|$_methodBodies';
  }

  @override
  bool matchesImplementation(SynthesisResult other) =>
      other is SystemCSynthesisResult &&
      other._portsString == _portsString &&
      other._moduleBodyString == _moduleBodyString;

  @override
  int get matchHashCode => _portsString.hashCode ^ _moduleBodyString.hashCode;

  @override
  String toFileContents() => _toSystemC();

  @override
  List<SynthFileContents> toSynthFileContents() => List.unmodifiable([
        SynthFileContents(
          name: instanceTypeName,
          description: 'SystemC module definition for $instanceTypeName',
          contents: _toSystemC(),
        )
      ]);

  // ────────────────────────────────────────────────────────────────────
  // Clock/reset detection
  // ────────────────────────────────────────────────────────────────────

  /// Internal clock signals promoted to ports (from SimpleClockGenerator).
  late final Set<String> _promotedClockSignals;

  /// Pre-scans sub-module instantiations to identify clock/reset signals
  /// and internal clocks that should be promoted to ports.
  void _findClockResetSignals() {
    final promotedClocks = <String>{};
    for (final ssmi in _synthModuleDefinition.subModuleInstantiations) {
      final m = ssmi.module;
      // Detect SimpleClockGenerator and promote its output to a port
      if (m is SimpleClockGenerator) {
        for (final entry in ssmi.outputMapping.entries) {
          promotedClocks.add(entry.value.name);
        }
      }
    }
    _promotedClockSignals = promotedClocks;
  }

  // ────────────────────────────────────────────────────────────────────
  // Type mapping
  // ────────────────────────────────────────────────────────────────────

  /// Sanitize a signal/port name to be a valid C++ identifier.
  /// Replaces `[N]` with `_N_` (LogicArray element indexing).
  static String _scName(String name) =>
      name.replaceAllMapped(RegExp(r'\[(\d+)\]'), (m) => '_${m[1]}_');

  /// Maps a signal width to the appropriate SystemC data type.
  static String systemCType(int width) {
    if (width == 1) {
      return 'bool';
    } else if (width <= 64) {
      return 'sc_uint<$width>';
    } else {
      return 'sc_biguint<$width>';
    }
  }

  /// SystemC input port type for a given width.
  static String systemCInType(int width) => 'sc_in<${systemCType(width)}>';

  /// SystemC output port type for a given width.
  static String systemCOutType(int width) => 'sc_out<${systemCType(width)}>';

  /// SystemC signal type for a given width.
  static String systemCSignalType(int width) =>
      'sc_signal<${systemCType(width)}>';

  // ────────────────────────────────────────────────────────────────────
  // Port declarations
  // ────────────────────────────────────────────────────────────────────

  String _systemCPorts() {
    final lines = <String>[];
    for (final sig in _synthModuleDefinition.inputs) {
      final n = _scName(sig.name);
      lines.add('  ${systemCInType(sig.width)} $n{"$n"};');
    }
    // Promote internal clock signals (from SimpleClockGenerator) to ports
    for (final clkName in _promotedClockSignals) {
      final n = _scName(clkName);
      lines.add('  ${systemCInType(1)} $n{"$n"};');
    }
    for (final sig in _synthModuleDefinition.outputs) {
      final n = _scName(sig.name);
      lines.add('  ${systemCOutType(sig.width)} $n{"$n"};');
    }
    return lines.join('\n');
  }

  // ────────────────────────────────────────────────────────────────────
  // Internal signals
  // ────────────────────────────────────────────────────────────────────

  String _buildInternalSignals() {
    final declarations = <String>[];
    for (final sig in _synthModuleDefinition.internalSignals
        .where((e) => e.needsDeclaration)
        .where((e) => !_promotedClockSignals.contains(e.name))
        .sorted((a, b) => a.name.compareTo(b.name))) {
      final n = _scName(sig.name);
      declarations.add('  ${systemCSignalType(sig.width)} $n{"$n"};');
    }

    // Declare individual signals for array elements that are written to
    // (FlipFlop/Sequential outputs targeting array elements)
    for (final elemName in _arrayElementsWritten.keys) {
      final n = _scName(elemName);
      final width = _arrayElementsWritten[elemName]!;
      declarations.add('  ${systemCSignalType(width)} $n{"$n"};');
    }
    return declarations.join('\n');
  }

  /// Maps array element names (e.g. "delayLine[0]") to their widths.
  /// These need separate signal declarations because SystemC can't do
  /// partial writes to sc_signal.
  late final Map<String, int> _arrayElementsWritten =
      _findArrayElementsWritten();

  /// Groups array elements by parent: parentName → list of (index, elemWidth).
  late final Map<String, List<({int index, int width, String elemName})>>
      _arrayElementsByParent = _groupArrayElementsByParent();

  Map<String, int> _findArrayElementsWritten() {
    final result = <String, int>{};

    void addIfArrayElement(SynthLogic sl) {
      if (sl is SynthLogicArrayElement) {
        result[sl.name] = sl.logic.width;
      }
    }

    for (final ssmi in _synthModuleDefinition.subModuleInstantiations) {
      final m = ssmi.module;

      // All submodule output mappings
      ssmi.outputMapping.values.forEach(addIfArrayElement);

      // Inline gate result logics
      if (ssmi is SystemCSynthSubModuleInstantiation) {
        final rl = ssmi.inlineResultLogic;
        if (rl != null) {
          addIfArrayElement(rl);
        }
      }

      // Scan conditionals for nested array element receivers
      if (m is Combinational) {
        _collectArrayReceiversFromConditionals(m.conditionals, result);
      } else if (m is Sequential) {
        _collectArrayReceiversFromConditionals(m.conditionals, result);
      }
    }

    // Wire assignments targeting array elements
    for (final assignment in _synthModuleDefinition.assignments) {
      addIfArrayElement(assignment.dst);
    }

    return result;
  }

  /// Recursively walks a conditionals tree to find all receivers that
  /// are array elements and adds them to [result].
  void _collectArrayReceiversFromConditionals(
      List<Conditional> conditionals, Map<String, int> result) {
    for (final c in conditionals) {
      for (final receiver in c.receivers) {
        final sl = _synthModuleDefinition.logicToSynthMap[receiver];
        if (sl is SynthLogicArrayElement && !result.containsKey(sl.name)) {
          result[sl.name] = sl.logic.width;
        }
      }
      // Recurse into sub-conditionals
      _collectArrayReceiversFromConditionals(c.conditionals, result);
    }
  }

  /// Groups array elements by their root parent signal,
  /// computing flat bit offsets for nested elements.
  Map<String, List<({int index, int width, String elemName})>>
      _groupArrayElementsByParent() {
    final result = <String, List<({int index, int width, String elemName})>>{};

    void addElement(SynthLogicArrayElement sl) {
      // Walk up to root and compute flat bit offset
      var flatOffset = 0;
      SynthLogic current = sl;
      while (current is SynthLogicArrayElement) {
        final idx = current.logic.arrayIndex;
        if (idx == null) {
          return; // pruned element — skip
        }
        flatOffset += idx * current.logic.width;
        current = current.parentArray.replacement ?? current.parentArray;
      }
      final rootName = current.name;

      final entry = (
        // Use flat bit offset as "index" for assembly ordering
        index: flatOffset,
        width: sl.logic.width,
        elemName: sl.name,
      );
      // Avoid duplicates
      final list = result.putIfAbsent(rootName, () => []);
      if (!list.any((e) => e.elemName == entry.elemName)) {
        list.add(entry);
      }
    }

    // Use logicToSynthMap to find the SynthLogicArrayElement for each written
    // element, rather than re-scanning submodule instantiations.
    for (final sl in _synthModuleDefinition.logicToSynthMap.values) {
      if (sl is SynthLogicArrayElement && sl.replacement == null) {
        // Skip elements whose parent has been pruned or not named
        final parent = sl.parentArray.replacement ?? sl.parentArray;
        if (parent.declarationCleared) {
          continue;
        }
        if (_arrayElementsWritten.containsKey(sl.name)) {
          addElement(sl);
        }
      }
    }

    // Sort each list by flat bit offset
    for (final list in result.values) {
      list.sort((a, b) => a.index.compareTo(b.index));
    }
    return result;
  }

  // ────────────────────────────────────────────────────────────────────
  // Inline gate expressions
  // ────────────────────────────────────────────────────────────────────

  /// Returns true if a module is a SystemVerilog gate that generates no
  /// definition and should be inlined (like Add).
  static bool _isInlinableSystemVerilogGate(Module m) =>
      m is SystemVerilog &&
      m is! InlineSystemVerilog &&
      m is! Always &&
      m is! FlipFlop &&
      m.generatedDefinitionType == DefinitionGenerationType.none;

  /// Converts a [SynthLogic] to a SystemC read expression.
  /// Constants become typed literals; signals get `.read()`.
  /// Array elements become range expressions on their parent.
  static String _synthLogicReadExpr(SynthLogic sl) {
    if (sl.isConstant) {
      final c = sl.logics.whereType<Const>().first;
      return _typedConstExpr(c.value, c.width);
    }
    if (sl is SynthLogicArrayElement) {
      return _arrayElementReadExpr(sl);
    }
    return '${_scName(sl.name)}.read()';
  }

  /// Generates a typed constant expression for SystemC.
  /// Handles x/z values by treating them as 0.
  static String _typedConstExpr(LogicValue val, int width) {
    if (val.isValid) {
      if (width == 0) {
        return '0';
      }
      final bigVal = val.toBigInt();
      if (width > 64) {
        // Use hex string constructor for sc_biguint
        var hex = bigVal.toUnsigned(width).toRadixString(16);
        if (hex.length.isOdd) {
          hex = '0$hex';
        }
        return '${systemCType(width)}("0x$hex")';
      }
      // For uint64 values above INT64_MAX, add ULL suffix
      if (bigVal > BigInt.from(0x7FFFFFFFFFFFFFFF)) {
        return '${systemCType(width)}'
            '(${bigVal.toUnsigned(width)}ULL)';
      }
      return '${systemCType(width)}(${bigVal.toUnsigned(width)})';
    }
    // For values with x/z, use 0 (SystemC doesn't have x/z)
    return '${systemCType(width)}(0)';
  }

  /// Generates a range read expression for an array element. e.g.
  /// deserialized[0] (8-bit in 32-bit parent) → deserialized.read().range(7, 0)
  /// Generates a range read expression for an array element, handling
  /// arbitrary nesting depth.  e.g. `laIn[2][1]` in a `[3,2]x8` array
  /// → `laIn.read().range(47, 40)`.
  static String _arrayElementReadExpr(SynthLogicArrayElement sl) {
    final elemWidth = sl.logic.width;

    // Walk up the parent chain to find the root signal and accumulate
    // the flat bit offset.
    var flatOffset = 0;
    SynthLogic current = sl;
    while (current is SynthLogicArrayElement) {
      final idx = current.logic.arrayIndex!;
      final w = current.logic.width;
      flatOffset += idx * w;
      current = current.parentArray.replacement ?? current.parentArray;
    }
    final rootName = _scName(current.name);
    final rootWidth = current.width;

    final lo = flatOffset;
    final hi = lo + elemWidth - 1;

    // If the root is 1-bit (bool), subscript/range is not valid
    if (rootWidth == 1) {
      return '$rootName.read()';
    }
    if (elemWidth == 1) {
      return 'static_cast<bool>($rootName.read()[$lo])';
    }
    final rangeType = elemWidth <= 64 ? 'sc_uint' : 'sc_biguint';
    return '$rangeType<$elemWidth>($rootName.read().range($hi, $lo))';
  }

  /// Returns the sensitivity signal name for a SynthLogic.
  /// For array elements, walks up to the root (non-array-element) parent.
  static String _sensitivityName(SynthLogic sl) {
    var current = sl;
    while (current is SynthLogicArrayElement) {
      current = current.parentArray.replacement ?? current.parentArray;
    }
    return _scName(current.name);
  }

  /// Generates an SC_METHOD for inline gates (like SV `assign` stmts).
  _MethodResult? _buildInlineGates() {
    final inlineGates = _synthModuleDefinition.subModuleInstantiations
        .where((s) =>
            s.needsInstantiation &&
            (s.module is InlineSystemVerilog ||
                _isInlinableSystemVerilogGate(s.module)))
        .cast<SystemCSynthSubModuleInstantiation>()
        .toList();

    if (inlineGates.isEmpty) {
      return null;
    }

    final sensitivities = <String>{};
    final bodyLines = <String>[];

    for (final ssmi in inlineGates) {
      final m = ssmi.module;

      // Collect inputs — constants become literals, signals get .read()
      final inputExprs = <String, String>{};
      for (final entry in ssmi.inputMapping.entries) {
        final sl = entry.value;
        if (!sl.isConstant) {
          sensitivities.add(_sensitivityName(sl));
        }
        inputExprs[entry.key] = _synthLogicReadExpr(sl);
      }

      if (m is InlineSystemVerilog) {
        final resultSynthLogic = ssmi.inlineResultLogic;
        if (resultSynthLogic == null) {
          continue;
        }
        final expr = _gateExpression(m, inputExprs);
        final dst = _scName(resultSynthLogic.name);
        bodyLines.add('    $dst = $expr;');
      } else if (m is Add) {
        // Add has two outputs: sum and carry.
        // Emit inline expressions for each used output.
        final vals = inputExprs.values.toList();
        final sumPortName = m.sum.name;
        for (final entry in ssmi.outputMapping.entries) {
          final portName = entry.key;
          final dst = _scName(entry.value.name);
          if (portName == sumPortName) {
            bodyLines.add('    $dst = ${vals[0]} + ${vals[1]};');
          } else {
            // carry: high bit of (width+1)-bit addition
            final w = m.width;
            final w1 = w + 1;
            final utype = systemCType(w1);
            final carryExpr = 'static_cast<bool>'
                '($utype($utype(${vals[0]})'
                ' + $utype(${vals[1]}))[$w])';
            bodyLines.add('    $dst = $carryExpr;');
          }
        }
      }
      ssmi.clearInstantiation();
    }

    if (bodyLines.isEmpty) {
      return null;
    }

    final setupBuf = StringBuffer()..writeln('    SC_METHOD(assign_method);');
    for (final sig in sensitivities) {
      setupBuf.writeln('    sensitive << $sig;');
    }

    return _MethodResult(
      setup: setupBuf.toString(),
      body: '  void assign_method() {\n'
          '${bodyLines.join('\n')}\n'
          '  }',
    );
  }

  /// Maps an InlineSystemVerilog gate to a C++ expression.
  ///
  /// Handles all gate types that have SV-specific syntax which needs
  /// translation to valid SystemC/C++.
  String _gateExpression(InlineSystemVerilog m, Map<String, String> inputs) {
    // ── Single-output bitwise gates (C++ operators identical to SV) ──
    if (m is NotGate) {
      // For bool (width-1), use logical not; for wider, bitwise not
      if ((m as Module).outputs.values.first.width == 1) {
        return '!${inputs.values.first}';
      }
      return '~${inputs.values.first}';
    }

    // ── Binary operator gates (C++ operators identical to SV) ──
    const binaryOps = <Type, String>{
      And2Gate: '&',
      Or2Gate: '|',
      Xor2Gate: '^',
      Subtract: '-',
      Multiply: '*',
    };
    final binOp = binaryOps[m.runtimeType];
    if (binOp != null) {
      final vals = inputs.values.toList();
      return '${vals[0]} $binOp ${vals[1]}';
    }
    if (m is Divide || m is Modulo) {
      final vals = inputs.values.toList();
      final op = m is Divide ? '/' : '%';
      // Guard against zero divisor (sc_uint defaults to 0 at time-0)
      return '(${vals[1]} != 0 ? ${vals[0]} $op ${vals[1]} : 0)';
    }
    if (m is Power) {
      final vals = inputs.values.toList();
      final w = (m as Module).inputs.values.first.width;
      return '${systemCType(w)}'
          '(static_cast<uint64_t>'
          '(pow(static_cast<double>(${vals[0]}),'
          ' static_cast<double>(${vals[1]}))))';
    }

    // ── Comparison (operators identical) ──
    const cmpOps = <Type, String>{
      Equals: '==',
      NotEquals: '!=',
      LessThan: '<',
      GreaterThan: '>',
      LessThanOrEqual: '<=',
      GreaterThanOrEqual: '>=',
    };
    final cmpOp = cmpOps[m.runtimeType];
    if (cmpOp != null) {
      final vals = inputs.values.toList();
      return '${vals[0]} $cmpOp ${vals[1]}';
    }

    // ── Shifts ──
    // Cast shift amount to int to avoid ambiguous overloads.
    // Width 1 maps to bool in SystemC (no .to_int()), so use (int) cast.
    // Clamp: if shift amount >= operand width, result is 0 (or sign-fill
    // for arshift), avoiding .to_int() overflow on huge shift amounts.
    if (m is LShift || m is RShift || m is ARShift) {
      final vals = inputs.values.toList();
      final w = (m as Module).inputs.values.first.width;
      final outType = systemCType(w);
      final shiftAmtWidth = (m as Module).inputs.values.toList()[1].width;
      final shiftExpr =
          shiftAmtWidth == 1 ? '(int)(${vals[1]})' : '(${vals[1]}).to_int()';
      if (m is ARShift) {
        final signedType = w <= 64 ? 'sc_int<$w>' : 'sc_bigint<$w>';
        final shiftOp = '$outType(($signedType(${vals[0]})) >> $shiftExpr)';
        if (shiftAmtWidth > 31) {
          // Sign-fill: shift by width-1 to replicate MSB when shift >= width
          final overflow = '$outType(($signedType(${vals[0]})) >> ${w - 1})';
          return '(${vals[1]} >= $w) ? $overflow : $shiftOp';
        }
        return shiftOp;
      }
      final op = m is LShift ? '<<' : '>>';
      final shiftOp = '$outType(${vals[0]} $op $shiftExpr)';
      if (shiftAmtWidth > 31) {
        return '(${vals[1]} >= $w) ? $outType(0) : $shiftOp';
      }
      return shiftOp;
    }

    // ── Unary reductions ──
    if (m is AndUnary || m is OrUnary || m is XorUnary) {
      final inputWidth = (m as Module).inputs.values.first.width;
      // 1-bit: reduce is identity (and bool has no .xor_reduce() in SystemC)
      if (inputWidth == 1) {
        return 'static_cast<bool>(${inputs.values.first})';
      }
      if (m is AndUnary) {
        return '${inputs.values.first}.and_reduce()';
      } else if (m is OrUnary) {
        return '${inputs.values.first}.or_reduce()';
      } else {
        return '${inputs.values.first}.xor_reduce()';
      }
    }

    // ── Bus subset (slice / index) ──
    if (m is BusSubset) {
      final a = inputs.values.first;
      final inputWidth = (m as Module).inputs.values.first.width;
      // If input is already 1-bit (bool), extracting bit 0 is identity
      if (inputWidth == 1 && m.startIndex == 0 && m.endIndex == 0) {
        return a;
      }
      if (m.startIndex == m.endIndex) {
        return 'static_cast<bool>($a[${m.startIndex}])';
      }
      if (m.startIndex > m.endIndex) {
        // Reverse order — build bit-by-bit concat
        // bits[0]=a[endIndex], ..., bits[N]=a[startIndex]
        // SystemC concat is MSB-first: output MSB = input[endIndex]
        // Use sc_uint<1> (not bool) so SystemC concat operator is invoked
        final bits = List.generate(m.startIndex - m.endIndex + 1,
            (i) => 'sc_uint<1>($a[${m.endIndex + i}])');
        return '(${bits.join(', ')})';
      }
      final w = m.endIndex - m.startIndex + 1;
      final rangeType = w <= 64 ? 'sc_uint' : 'sc_biguint';
      return '$rangeType<$w>($a.range(${m.endIndex}, ${m.startIndex}))';
    }

    // ── Dynamic bit index ──
    if (m is IndexGate) {
      final vals = inputs.values.toList();
      return 'static_cast<bool>(${vals[0]}[${vals[1]}])';
    }

    // ── Mux (ternary) ──
    if (m is Mux) {
      final vals = inputs.values.toList();
      final w = m.out.width;
      final utype = systemCType(w);
      // Cast both branches to avoid C++ ternary type mismatch
      // (e.g., when one branch is bool and the other is sc_uint<1>)
      return '${vals[0]}'
          ' ? $utype(${vals[2]})'
          ' : $utype(${vals[1]})';
    }

    // ── Replication ──
    if (m is ReplicationOp) {
      final a = inputs.values.first;
      final inputWidth = (m as Module).inputs.values.first.width;
      final outputWidth = m.replicated.width;
      final numReps = outputWidth ~/ inputWidth;
      if (inputWidth == 1) {
        // Single-bit replicate: all-1s or all-0s
        final utype = systemCType(outputWidth);
        return '$utype('
            '$a '
            '? $utype(-1) '
            ': $utype(0))';
      }
      // Multi-bit replicate: concat N copies
      final copies = List.filled(numReps, a);
      return '(${copies.join(', ')})';
    }

    // ── Swizzle (concatenation) ──
    if (m is Swizzle) {
      // SystemC concatenation: (sig1, sig2, sig3)
      // bool operands must be cast to sc_uint<1> to use SystemC concat
      // (otherwise C++ comma operator is invoked instead)
      final modInputs = (m as Module).inputs.values.toList();
      final exprList = <String>[];
      var i = 0;
      for (final expr in inputs.values) {
        final w = modInputs[i].width;
        if (w == 0) {
          i++;
          continue; // skip zero-width padding
        }
        // Wrap 1-bit (bool) operands in sc_uint<1>() for concat
        if (w == 1) {
          exprList.add('sc_uint<1>($expr)');
        } else {
          exprList.add(expr);
        }
        i++;
      }
      if (exprList.length == 1) {
        return exprList.first;
      }
      // Swizzle stores inputs LSB-first (in0=LSB), but SystemC concat
      // is MSB-first: (msb, ..., lsb). So reverse.
      return '(${exprList.reversed.join(', ')})';
    }

    // Fallback: use SV inline (may not be valid C++ — flag for review)
    return '/* TODO: ${m.runtimeType} */ ${m.inlineVerilog(inputs)}';
  }

  // ────────────────────────────────────────────────────────────────────
  // Clock / trigger edge resolution
  // ────────────────────────────────────────────────────────────────────

  /// Resolves a trigger [SynthLogic] to the effective clock port and edge.
  ///
  /// If the trigger signal is a module input port, it can be used directly
  /// with `SC_CTHREAD`. If it is an internal signal derived from a [NotGate],
  /// the method traces through the inversion chain to find the original port
  /// and flips the edge accordingly (`negedge(~clk) = posedge(clk)`).
  ({String clockName, bool isPort, bool isPosedge}) _resolveClockAndEdge(
      SynthLogic triggerSL, bool isPosedge) {
    final sl = triggerSL.replacement ?? triggerSL;

    if (sl.isPort(_synthModuleDefinition.module)) {
      return (clockName: sl.name, isPort: true, isPosedge: isPosedge);
    }

    // Try to trace through a NotGate inversion
    for (final logic in sl.logics) {
      final src = logic.srcConnection;
      if (src != null && src.parentModule is NotGate) {
        final notInput = src.parentModule!.inputs.values.first;
        final notInputSrc = notInput.srcConnection;
        if (notInputSrc != null) {
          final srcSL = _synthModuleDefinition.logicToSynthMap[notInputSrc];
          if (srcSL != null) {
            // Inversion flips the edge
            return _resolveClockAndEdge(srcSL, !isPosedge);
          }
        }
      }
    }

    // Fallback — use the signal as-is (SC_THREAD will be needed)
    return (clockName: sl.name, isPort: false, isPosedge: isPosedge);
  }

  // ────────────────────────────────────────────────────────────────────
  // Combinational / Sequential processes
  // ────────────────────────────────────────────────────────────────────

  _MethodResult? _buildProcesses() {
    final setupBuf = StringBuffer();
    final bodyBuf = StringBuffer();
    var idx = 0;

    // Collect clocked processes for consolidation by (clock, reset) pair.
    // Sequentials and FlipFlops sharing the same clock/reset are merged
    // into a single SC_CTHREAD, eliminating repeated async_reset_signal_is.
    final clockedGroups = <String, _ClockedGroupData>{};

    for (final ssmi
        in _synthModuleDefinition.subModuleInstantiations.toList()) {
      ssmi as SystemCSynthSubModuleInstantiation;
      final m = ssmi.module;

      if (m is Combinational) {
        final name = 'comb_$idx';
        idx++;

        final sensitivities = ssmi.inputMapping.values
            .where((sl) => !sl.declarationCleared && !sl.isConstant)
            .map(_sensitivityName)
            .toSet();

        setupBuf.writeln('    SC_METHOD($name);');
        for (final sig in sensitivities) {
          setupBuf.writeln('    sensitive << $sig;');
        }

        // Build maps keyed by port name (what verilogContents expects)
        final inputsMap = ssmi.inputMapping
            .map((k, sl) => MapEntry(k, _synthLogicReadExpr(sl)));
        final outputsMap =
            ssmi.outputMapping.map((k, sl) => MapEntry(k, _scName(sl.name)));

        bodyBuf.writeln('  void $name() {');
        for (final c in m.conditionals) {
          bodyBuf.write(_conditionalToSC(c, 2, inputsMap, outputsMap));
        }
        bodyBuf
          ..writeln('  }')
          ..writeln();
        ssmi.clearInstantiation();
      } else if (m is Sequential) {
        final resetEntry = ssmi.inputMapping.entries
            .where((e) => e.key.contains('reset'))
            .firstOrNull;

        // Detect async reset: either explicitly via asyncReset flag, or
        // implicitly when the reset signal is also listed as a trigger
        // (e.g. Sequential.multi([clk, reset], reset: reset, ...)).
        final isAsync = m.asyncReset ||
            (resetEntry != null &&
                ssmi.inputMapping.entries.any((e) =>
                    e.key.contains('trigger') &&
                    e.value.name == resetEntry.value.name));

        // Resolve ALL trigger entries to (signalName, edge, isPort).
        final triggerEdges = m.triggerEdges;
        final triggerEntries = ssmi.inputMapping.entries
            .where((e) => e.key.contains('trigger'))
            .toList();

        final resolvedTriggers =
            <({String signalName, bool isPosedge, bool isPort})>[];

        for (final te in triggerEntries) {
          final triggerSL = te.value;
          // Skip if this trigger is the async reset signal
          if (resetEntry != null && triggerSL.name == resetEntry.value.name) {
            continue;
          }
          // Skip constant triggers (e.g. clk <= Const(0) — never toggles)
          if (triggerSL.isConstant) {
            continue;
          }
          final isPosedge = triggerEdges
                  .where((t) => t.portName == te.key)
                  .firstOrNull
                  ?.isPosedge ??
              true;
          final resolved = _resolveClockAndEdge(triggerSL, isPosedge);
          // Skip if the resolved signal is constant
          final resolvedSL = _synthModuleDefinition.logicToSynthMap.values
              .where((sl) => sl.name == resolved.clockName)
              .firstOrNull;
          if (resolvedSL != null && resolvedSL.isConstant) {
            continue;
          }
          resolvedTriggers.add((
            signalName: resolved.clockName,
            isPosedge: resolved.isPosedge,
            isPort: resolved.isPort,
          ));
        }

        // Deduplicate by (signalName, isPosedge)
        final seen = <String>{};
        final uniqueTriggers =
            <({String signalName, bool isPosedge, bool isPort})>[];
        for (final t in resolvedTriggers) {
          final key = '${t.signalName}|${t.isPosedge}';
          if (seen.add(key)) {
            uniqueTriggers.add(t);
          }
        }

        // Build group key from all trigger signals + reset
        final triggerKey = uniqueTriggers
            .map((t) => '${t.signalName}:${t.isPosedge}')
            .join(',');
        final groupKey = '$triggerKey|${resetEntry?.value.name ?? '_none_'}';
        final group = clockedGroups.putIfAbsent(
            groupKey,
            () => _ClockedGroupData(
                  resetName: resetEntry?.value.name,
                  isAsyncReset: isAsync,
                ));
        // Add all triggers to the group (dedup handled by emission)
        for (final t in uniqueTriggers) {
          if (!group.triggers.any((existing) =>
              existing.signalName == t.signalName &&
              existing.isPosedge == t.isPosedge)) {
            group.triggers.add(t);
          }
        }
        if (isAsync) {
          group.isAsyncReset = true;
        }

        final inputsMap = ssmi.inputMapping
            .map((k, sl) => MapEntry(k, _synthLogicReadExpr(sl)));
        final outputsMap =
            ssmi.outputMapping.map((k, sl) => MapEntry(k, _scName(sl.name)));

        for (final outName in outputsMap.values) {
          group.resetLines.add('    $outName = 0;');
        }
        final condBuf = StringBuffer();
        for (final c in m.conditionals) {
          condBuf.write(_conditionalToSC(c, 3, inputsMap, outputsMap));
        }
        group.whileBodyLines.add(condBuf.toString());
        ssmi.clearInstantiation();
      } else if (m is FlipFlop) {
        // Resolve port signals via the input/output mapping
        final clkSl = ssmi.inputMapping.entries
            .firstWhere((e) => e.key.contains('clk'))
            .value;
        final dSl = ssmi.inputMapping.entries
            .firstWhere((e) => e.key.contains('d'))
            .value;
        final resetEntry = ssmi.inputMapping.entries
            .where((e) => e.key.contains('reset') && !e.key.contains('Value'))
            .firstOrNull;
        final enEntry = ssmi.inputMapping.entries
            .where((e) => e.key.contains('en'))
            .firstOrNull;
        final resetValueEntry = ssmi.inputMapping.entries
            .where(
                (e) => e.key.contains('resetValue') || e.key.contains('Value'))
            .firstOrNull;
        final qSl = ssmi.outputMapping.values.first;

        final groupKey =
            '${clkSl.name}:true|${resetEntry?.value.name ?? '_none_'}';
        final group = clockedGroups.putIfAbsent(
            groupKey,
            () => _ClockedGroupData(
                  resetName: resetEntry?.value.name,
                  isAsyncReset: m.asyncReset,
                ));
        // FlipFlop always posedge
        if (!group.triggers
            .any((t) => t.signalName == clkSl.name && t.isPosedge)) {
          group.triggers.add((
            signalName: clkSl.name,
            isPosedge: true,
            isPort: clkSl.isPort(_synthModuleDefinition.module),
          ));
        }
        if (m.asyncReset) {
          group.isAsyncReset = true;
        }

        // Reset value
        String resetValExpr;
        if (resetValueEntry != null) {
          resetValExpr = _synthLogicReadExpr(resetValueEntry.value);
        } else if (m.constantResetValue != null) {
          resetValExpr = m.constantResetValue!.toBigInt().toString();
        } else {
          resetValExpr = '0';
        }
        group.resetLines.add('    ${_scName(qSl.name)} = $resetValExpr;');

        // Build the data assignment (with optional enable gate)
        final assignExpr =
            '      ${_scName(qSl.name)} = ${_synthLogicReadExpr(dSl)};\n';
        final bodyLine = enEntry != null
            ? '      if (${_synthLogicReadExpr(enEntry.value)}) {\n'
                '  $assignExpr'
                '      }\n'
            : assignExpr;

        // Wrap in sync reset check if needed
        if (resetEntry != null && !m.asyncReset) {
          group.whileBodyLines
              .add('      if (${_scName(resetEntry.value.name)}.read()) {\n'
                  '        ${_scName(qSl.name)} = $resetValExpr;\n'
                  '      } else {\n'
                  '  $bodyLine'
                  '      }\n');
        } else {
          group.whileBodyLines.add(bodyLine);
        }
        ssmi.clearInstantiation();
      }
    }

    // Emit one SC_CTHREAD or SC_THREAD per (clock, reset) group
    for (final group in clockedGroups.values) {
      final name = 'clocked_$idx';
      idx++;

      final triggers = group.triggers;

      if (triggers.isEmpty) {
        // All triggers were constant — skip this group
        continue;
      }

      // Determine if we can use SC_CTHREAD:
      // - exactly one trigger signal
      // - that signal is a port (sc_in)
      // - only one edge direction
      final distinctSignals = triggers.map((t) => t.signalName).toSet();
      final useCthread = distinctSignals.length == 1 &&
          triggers.first.isPort &&
          triggers.length == 1;

      if (useCthread) {
        final t = triggers.first;
        final clockRef = _scName(t.signalName);
        final edge = t.isPosedge ? '.pos()' : '.neg()';
        setupBuf.writeln('    SC_CTHREAD($name, $clockRef$edge);');
        if (group.resetName != null && group.isAsyncReset) {
          setupBuf.writeln('    async_reset_signal_is('
              '${_scName(group.resetName!)}, true);');
        }

        bodyBuf.writeln('  void $name() {');
        group.resetLines.forEach(bodyBuf.writeln);
        bodyBuf
          ..writeln('    wait();')
          ..writeln('    while (true) {');
        group.whileBodyLines.forEach(bodyBuf.write);
        bodyBuf
          ..writeln('      wait();')
          ..writeln('    }')
          ..writeln('  }')
          ..writeln();
      } else {
        // SC_THREAD with explicit wait on events
        setupBuf.writeln('    SC_THREAD($name);');

        // Build wait expression from all trigger events
        String waitExpr;
        if (distinctSignals.length == 1) {
          // Same signal, but both edges
          final sig = _scName(triggers.first.signalName);
          final edges = triggers.map((t) => t.isPosedge).toSet();
          if (edges.length == 2) {
            waitExpr = '$sig.value_changed_event()';
          } else if (edges.first) {
            waitExpr = '$sig.posedge_event()';
          } else {
            waitExpr = '$sig.negedge_event()';
          }
        } else {
          // Multiple distinct trigger signals — OR them together
          final eventExprs = <String>[];
          for (final t in triggers) {
            final sig = _scName(t.signalName);
            eventExprs
                .add('$sig.${t.isPosedge ? 'posedge' : 'negedge'}_event()');
          }
          waitExpr = eventExprs.join(' | ');
        }

        bodyBuf.writeln('  void $name() {');
        group.resetLines.forEach(bodyBuf.writeln);
        bodyBuf
          ..writeln('    while (true) {')
          ..writeln('      wait($waitExpr);');
        group.whileBodyLines.forEach(bodyBuf.write);
        bodyBuf
          ..writeln('    }')
          ..writeln('  }')
          ..writeln();
      }
    }

    if (setupBuf.isEmpty && bodyBuf.isEmpty) {
      return null;
    }
    return _MethodResult(
      setup: setupBuf.toString(),
      body: bodyBuf.toString(),
    );
  }

  // ────────────────────────────────────────────────────────────────────
  // Regular sub-module instantiations
  // ────────────────────────────────────────────────────────────────────

  /// Returns true if the sub-module is handled inline (not a real child
  /// instantiation) — i.e. it is an inline gate, Always, FlipFlop, or clock.
  static bool _isHandledInline(SystemCSynthSubModuleInstantiation ssmi) =>
      !ssmi.needsInstantiation ||
      ssmi.module is InlineSystemVerilog ||
      ssmi.module is Always ||
      ssmi.module is FlipFlop ||
      ssmi.module is SimpleClockGenerator ||
      _isInlinableSystemVerilogGate(ssmi.module);

  String _buildSubModuleMembers(
      String Function(Module module) getInstanceTypeOfModule) {
    final lines = <String>[];
    for (final ssmi in _synthModuleDefinition.subModuleInstantiations) {
      ssmi as SystemCSynthSubModuleInstantiation;
      if (_isHandledInline(ssmi)) {
        continue;
      }
      final instanceType = getInstanceTypeOfModule(ssmi.module);
      lines.add('  $instanceType ${ssmi.name}{"${ssmi.name}"};');
    }
    return lines.join('\n');
  }

  /// Dummy signal declarations needed for unconnected submodule output ports.
  /// Populated by [_buildSubModuleBindings].
  final List<String> _unconnectedOutputSignals = [];

  /// Signal declarations for constants bound to submodule input ports.
  /// Populated by [_buildSubModuleBindings].
  final List<String> _constInputSignals = [];

  /// Initialization statements for constant signals (in constructor body).
  /// Populated by [_buildSubModuleBindings].
  final List<String> _constInputInits = [];

  String _buildSubModuleBindings(
      String Function(Module module) getInstanceTypeOfModule) {
    final lines = <String>[];
    var unconnIdx = 0;
    for (final ssmi in _synthModuleDefinition.subModuleInstantiations) {
      ssmi as SystemCSynthSubModuleInstantiation;
      if (_isHandledInline(ssmi)) {
        continue;
      }

      // Bind connected ports (inputs, outputs, inouts)
      final allPorts = {
        ...ssmi.inputMapping,
        ...ssmi.outputMapping,
        ...ssmi.inOutMapping,
      };
      for (final entry in allPorts.entries) {
        if (!entry.value.declarationCleared) {
          if (entry.value.isConstant) {
            // Constants can't be bound directly to sc_in ports;
            // create a signal, initialize it, and bind that.
            final constName = _scName('_const_${ssmi.name}'
                '_${entry.key}_${_constInputSignals.length}');
            final w = entry.value.width;
            final c = entry.value.logics.whereType<Const>().first;
            final constVal = _typedConstExpr(c.value, c.width);
            _constInputSignals
                .add('  ${systemCSignalType(w)} $constName{"$constName"};');
            _constInputInits.add('    $constName.write($constVal);');
            lines.add('    ${ssmi.name}.${entry.key}($constName);');
          } else {
            lines.add('    '
                '${ssmi.name}.${entry.key}(${_scName(entry.value.name)});');
          }
        }
      }

      // Bind unconnected ports to dummy signals
      // (SystemC requires all sc_in/sc_out ports to be bound)
      for (final entry in [
        ...ssmi.outputMapping.entries,
        ...ssmi.inputMapping.entries,
      ]) {
        if (entry.value.declarationCleared) {
          final dummyName = '_unused_${ssmi.name}_${entry.key}_$unconnIdx';
          final w = entry.value.width;
          _unconnectedOutputSignals
              .add('  ${systemCSignalType(w)} $dummyName{"$dummyName"};');
          lines.add('    ${ssmi.name}.${entry.key}($dummyName);');
          unconnIdx++;
        }
      }
    }
    return lines.join('\n');
  }

  // ────────────────────────────────────────────────────────────────────
  // Wire assignments
  // ────────────────────────────────────────────────────────────────────

  _MethodResult? _buildWireAssignments() {
    if (_synthModuleDefinition.assignments.isEmpty) {
      return null;
    }

    final bodyLines = <String>[];
    final sensitivities = <String>{};

    // Group partial assignments by destination for concatenated writes
    final partialsByDst = <String, List<PartialSynthAssignment>>{};

    for (final assignment in _synthModuleDefinition.assignments) {
      if (!assignment.src.isConstant) {
        sensitivities.add(_sensitivityName(assignment.src));
      }
      if (assignment is PartialSynthAssignment) {
        partialsByDst
            .putIfAbsent(_scName(assignment.dst.name), () => [])
            .add(assignment);
      } else {
        bodyLines.add('    ${_scName(assignment.dst.name)} = '
            '${_synthLogicReadExpr(assignment.src)};');
      }
    }

    // Emit grouped partial assignments as shift-or concatenation
    for (final entry in partialsByDst.entries) {
      final dstName = entry.key;
      final partials = entry.value
        ..sort((a, b) => a.dstLowerIndex.compareTo(b.dstLowerIndex));

      // Find total width from the destination SynthLogic
      final dstWidth = partials.last.dstUpperIndex + 1;
      final utype = systemCType(dstWidth);
      final parts = <String>[];
      for (final p in partials) {
        final srcExpr = _synthLogicReadExpr(p.src);
        if (p.dstLowerIndex == 0) {
          parts.add('$utype($srcExpr)');
        } else {
          parts.add('($utype($srcExpr) << ${p.dstLowerIndex})');
        }
      }
      bodyLines.add('    $dstName = ${parts.join(' | ')};');
    }

    final setupBuf = StringBuffer()..writeln('    SC_METHOD(wire_assign);');
    for (final sig in sensitivities) {
      setupBuf.writeln('    sensitive << $sig;');
    }

    return _MethodResult(
      setup: setupBuf.toString(),
      body: '  void wire_assign() {\n'
          '${bodyLines.join('\n')}\n'
          '  }',
    );
  }

  // ────────────────────────────────────────────────────────────────────
  // Conditional → SystemC
  // ────────────────────────────────────────────────────────────────────

  String _conditionalToSC(Conditional conditional, int indent,
      Map<String, String> inputsMap, Map<String, String> outputsMap) {
    final padding = '  ' * indent;

    if (conditional is ConditionalAssign) {
      final driverExpr = _resolveDriver(conditional.driver, inputsMap);
      final receiver = _resolveReceiver(conditional.receiver, outputsMap);
      return '$padding$receiver = $driverExpr;\n';
    } else if (conditional is If) {
      return _ifToSC(conditional, indent, inputsMap, outputsMap);
    } else if (conditional is Case) {
      return _caseToSC(conditional, indent, inputsMap, outputsMap);
    } else if (conditional is ConditionalGroup) {
      final buf = StringBuffer();
      for (final c in conditional.conditionals) {
        buf.write(_conditionalToSC(c, indent, inputsMap, outputsMap));
      }
      return buf.toString();
    }
    return '';
  }

  String _ifToSC(If ifBlock, int indent, Map<String, String> inputsMap,
      Map<String, String> outputsMap) {
    final padding = '  ' * indent;
    final buf = StringBuffer();

    for (final iff in ifBlock.iffs) {
      final header = iff == ifBlock.iffs.first
          ? 'if'
          : iff is Else
              ? ' else'
              : ' else if';
      final condition =
          iff is! Else ? ' (${_resolveDriver(iff.condition, inputsMap)})' : '';
      buf.write('$padding$header$condition {\n');
      for (final c in iff.then) {
        buf.write(_conditionalToSC(c, indent + 1, inputsMap, outputsMap));
      }
      buf.write('$padding}');
    }
    buf.writeln();
    return buf.toString();
  }

  String _caseToSC(Case caseBlock, int indent, Map<String, String> inputsMap,
      Map<String, String> outputsMap) {
    final padding = '  ' * indent;
    final buf = StringBuffer();
    final expr = _resolveDriver(caseBlock.expression, inputsMap);

    // Check if all case items have compile-time constant values
    final allConst =
        caseBlock.items.every((item) => _isConstCaseItem(item.value));

    // CaseZ requires mask matching — always use if/else
    // Non-const case items also require if/else
    if (caseBlock is CaseZ || !allConst) {
      return _caseToIfElseSC(caseBlock, indent, inputsMap, outputsMap, expr);
    }

    buf.writeln('${padding}switch ($expr) {');
    for (final item in caseBlock.items) {
      buf.writeln('$padding  case ${_constLit(item.value)}:');
      for (final c in item.then) {
        buf.write(_conditionalToSC(c, indent + 2, inputsMap, outputsMap));
      }
      buf.writeln('$padding    break;');
    }
    if (caseBlock.defaultItem != null) {
      buf.writeln('$padding  default:');
      for (final c in caseBlock.defaultItem!) {
        buf.write(_conditionalToSC(c, indent + 2, inputsMap, outputsMap));
      }
      buf.writeln('$padding    break;');
    }
    buf.writeln('$padding}');
    return buf.toString();
  }

  /// Checks whether a case item value is a compile-time constant.
  bool _isConstCaseItem(dynamic value) {
    if (value is Const) {
      return true;
    }
    if (value is LogicValue) {
      return true;
    }
    if (value is Logic) {
      if (value.srcConnection is Const) {
        return true;
      }
      final sl = _synthModuleDefinition.logicToSynthMap[value];
      if (sl != null && sl.isConstant) {
        return true;
      }
      return false;
    }
    return true; // int, string, etc.
  }

  /// Converts a Case/CaseZ block to if/else chain (for non-const items
  /// or CaseZ with z-masks).
  String _caseToIfElseSC(
      Case caseBlock,
      int indent,
      Map<String, String> inputsMap,
      Map<String, String> outputsMap,
      String expr) {
    final padding = '  ' * indent;
    final buf = StringBuffer();

    for (var i = 0; i < caseBlock.items.length; i++) {
      final item = caseBlock.items[i];
      final condition = _caseItemCondition(item.value, expr, inputsMap,
          isCaseZ: caseBlock is CaseZ);
      final header = i == 0 ? 'if' : ' else if';
      buf.write('$padding$header ($condition) {\n');
      for (final c in item.then) {
        buf.write(_conditionalToSC(c, indent + 1, inputsMap, outputsMap));
      }
      buf.write('$padding}');
    }
    if (caseBlock.defaultItem != null) {
      buf.write(' else {\n');
      for (final c in caseBlock.defaultItem!) {
        buf.write(_conditionalToSC(c, indent + 1, inputsMap, outputsMap));
      }
      buf.write('$padding}');
    }
    buf.writeln();
    return buf.toString();
  }

  /// Generates the condition expression for a case item comparison.
  String _caseItemCondition(
      dynamic value, String expr, Map<String, String> inputsMap,
      {bool isCaseZ = false}) {
    // Extract LogicValue from Const for CaseZ mask matching
    LogicValue? lv;
    if (value is Const) {
      lv = value.value;
    } else if (value is LogicValue) {
      lv = value;
    }
    if (isCaseZ && lv != null && !lv.isValid) {
      // CaseZ: create mask comparison  (expr & mask) == pattern
      // z bits become don't-care (mask out those bits)
      final width = lv.width;
      // z→0 in mask, 0/1→1 in mask
      var maskStr = '';
      var patStr = '';
      for (var i = width - 1; i >= 0; i--) {
        final bit = lv[i];
        if (bit == LogicValue.z || bit == LogicValue.x) {
          maskStr += '0';
          patStr += '0';
        } else {
          maskStr += '1';
          patStr += bit == LogicValue.one ? '1' : '0';
        }
      }
      final maskVal = BigInt.parse(maskStr, radix: 2);
      final patVal = BigInt.parse(patStr, radix: 2);
      return '($expr & $maskVal) == $patVal';
    }
    if (value is Logic && value is! Const) {
      final resolved = _resolveDriver(value, inputsMap);
      return '$expr == $resolved';
    }
    return '$expr == ${_constLit(value)}';
  }

  /// Resolves a driver Logic to a SystemC read expression using the
  /// SynthModuleDefinition's logicToSynthMap to find the canonical name.
  String _resolveDriver(Logic driver, Map<String, String> inputsMap) {
    if (driver is Const) {
      return _constLit(driver);
    }
    // Look up via logicToSynthMap — the SynthLogic has the canonical name
    final sl = _synthModuleDefinition.logicToSynthMap[driver];
    if (sl != null) {
      return _synthLogicReadExpr(sl);
    }
    // Try to find via source connection chain — handles cases where
    // the Logic object isn't directly in the map but its source is
    var src = driver.srcConnection;
    while (src != null) {
      final srcSl = _synthModuleDefinition.logicToSynthMap[src];
      if (srcSl != null) {
        return _synthLogicReadExpr(srcSl);
      }
      src = src.srcConnection;
    }
    // Fallback: try inputsMap by port name
    if (inputsMap.containsKey(driver.name)) {
      return inputsMap[driver.name]!;
    }
    return '${_scName(driver.name)}.read()';
  }

  /// Resolves a receiver Logic to a SystemC signal name using the
  /// SynthModuleDefinition's logicToSynthMap to find the canonical name.
  String _resolveReceiver(Logic receiver, Map<String, String> outputsMap) {
    // Look up via logicToSynthMap
    final sl = _synthModuleDefinition.logicToSynthMap[receiver];
    if (sl != null) {
      return _scName(sl.name);
    }
    // Fallback
    if (outputsMap.containsKey(receiver.name)) {
      return outputsMap[receiver.name]!;
    }
    return _scName(receiver.name);
  }

  String _constLit(dynamic value) {
    if (value is Const) {
      if (value.value.isValid) {
        return value.value.toBigInt().toString();
      }
      return '0'; // x/z → 0 in SystemC
    } else if (value is LogicValue) {
      if (value.isValid) {
        return value.toBigInt().toString();
      }
      return '0'; // x/z → 0 in SystemC
    } else if (value is Logic) {
      // If the Logic is driven by a Const, resolve to integer literal
      if (value.srcConnection is Const) {
        final cv = (value.srcConnection! as Const).value;
        return cv.isValid ? cv.toBigInt().toString() : '0';
      }
      // Check logicToSynthMap for a constant SynthLogic
      final sl = _synthModuleDefinition.logicToSynthMap[value];
      if (sl != null && sl.isConstant) {
        final constLogic = sl.logics.whereType<Const>().firstOrNull;
        if (constLogic != null) {
          return constLogic.value.isValid
              ? constLogic.value.toBigInt().toString()
              : '0';
        }
      }
      // Fallback: use signal read expression
      return '${value.name}.read()';
    }
    return value.toString();
  }

  // ────────────────────────────────────────────────────────────────────
  // Build all sections
  // ────────────────────────────────────────────────────────────────────

  void _buildModuleBody(
      String Function(Module module) getInstanceTypeOfModule) {
    _subMembers = _buildSubModuleMembers(getInstanceTypeOfModule);

    final inlineGates = _buildInlineGates();
    final processes = _buildProcesses();
    final wireAssigns = _buildWireAssignments();
    final arrayAssembly = _buildArrayAssemblyMethod();
    final subBindings = _buildSubModuleBindings(getInstanceTypeOfModule);

    // Build internal signals, appending dummy signals for unconnected
    // submodule outputs (populated by _buildSubModuleBindings above).
    final baseSigs = _buildInternalSignals();
    _internalSigs = [
      baseSigs,
      ..._unconnectedOutputSignals,
      ..._constInputSignals,
    ].where((s) => s.isNotEmpty).join('\n');

    final ctorParts = <String>[
      if (_constInputInits.isNotEmpty) _constInputInits.join('\n'),
      if (inlineGates != null) inlineGates.setup,
      if (processes != null) processes.setup,
      if (wireAssigns != null) wireAssigns.setup,
      if (arrayAssembly != null) arrayAssembly.setup,
      if (subBindings.isNotEmpty) subBindings,
    ];
    _ctorBody = ctorParts.join();

    final bodyParts = <String>[
      if (inlineGates != null) inlineGates.body,
      if (processes != null) processes.body,
      if (wireAssigns != null) wireAssigns.body,
      if (arrayAssembly != null) arrayAssembly.body,
    ];
    _methodBodies = bodyParts.where((s) => s.isNotEmpty).join('\n');
  }

  /// Builds an SC_METHOD that assembles individual array element signals
  /// back into their parent signal via concatenation.
  _MethodResult? _buildArrayAssemblyMethod() {
    if (_arrayElementsByParent.isEmpty) {
      return null;
    }

    final setupBuf = StringBuffer();
    final bodyBuf = StringBuffer();
    var methodIdx = 0;

    for (final entry in _arrayElementsByParent.entries) {
      final parentName = _scName(entry.key);
      final elements = entry.value;
      final methodName = 'array_assemble_$methodIdx';
      methodIdx++;

      setupBuf.writeln('    SC_METHOD($methodName);');
      for (final elem in elements) {
        setupBuf.writeln('    sensitive << ${_scName(elem.elemName)};');
      }

      // Build concatenation: (elem[N-1], ..., elem[1], elem[0])
      // SystemC concat is MSB-first, so highest index first
      // Wrap 1-bit (bool) elements in sc_uint<1>() for proper concat
      final concatParts = elements.reversed.map((e) {
        final read = '${_scName(e.elemName)}.read()';
        return e.width == 1 ? 'sc_uint<1>($read)' : read;
      }).toList();

      bodyBuf
        ..writeln('  void $methodName() {')
        ..writeln('    $parentName = (${concatParts.join(', ')});')
        ..writeln('  }')
        ..writeln();
    }

    return _MethodResult(
      setup: setupBuf.toString(),
      body: bodyBuf.toString(),
    );
  }

  // ────────────────────────────────────────────────────────────────────
  // Final assembly
  // ────────────────────────────────────────────────────────────────────

  String _toSystemC() {
    final moduleName = getInstanceTypeOfModule(module);
    final buf = StringBuffer()..writeln('SC_MODULE($moduleName) {');

    if (_portsString.isNotEmpty) {
      buf.writeln(_portsString);
    }
    if (_internalSigs.isNotEmpty) {
      buf
        ..writeln()
        ..writeln(_internalSigs);
    }
    if (_subMembers.isNotEmpty) {
      buf
        ..writeln()
        ..writeln(_subMembers);
    }

    buf
      ..writeln()
      ..writeln('  SC_CTOR($moduleName) {');
    if (_ctorBody.isNotEmpty) {
      buf.write(_ctorBody);
    }
    buf.writeln('  }');

    if (_methodBodies.isNotEmpty) {
      buf
        ..writeln()
        ..write(_methodBodies)
        ..writeln();
    }

    buf.writeln('};');
    return buf.toString();
  }
}

/// Helper to hold a constructor setup string and method body string.
class _MethodResult {
  final String setup;
  final String body;
  const _MethodResult({required this.setup, required this.body});
}

/// Collects clocked process data for consolidation by (clock, reset) pair.
class _ClockedGroupData {
  final String? resetName;
  bool isAsyncReset;

  /// All distinct trigger events (signal name, edge, and whether it's a port).
  final List<({String signalName, bool isPosedge, bool isPort})> triggers = [];

  final List<String> resetLines = [];
  final List<String> whileBodyLines = [];
  _ClockedGroupData({this.resetName, this.isAsyncReset = false});
}
