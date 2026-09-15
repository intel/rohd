// Copyright (C) 2021-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// systemverilog_synthesis_result.dart
// Definition for SystemVerilogCustomDefinitionSynthesisResult
//
// 2025 June
// Author: Max Korbel <max.korbel@intel.com>

import 'dart:io';

import 'package:collection/collection.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/systemverilog/systemverilog_synth_module_definition.dart';
import 'package:rohd/src/synthesizers/systemverilog/systemverilog_synth_sub_module_instantiation.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';

/// Extra utilities on [SynthLogic] to help with SystemVerilog synthesis.
extension on SynthLogic {
  /// Gets the SystemVerilog type for this signal.
  String definitionType() => isNet ? 'wire' : 'logic';
}

/// A [SynthesisResult] representing a [Module] that provides a custom
/// SystemVerilog definition.
class SystemVerilogCustomDefinitionSynthesisResult extends SynthesisResult {
  /// Creates a new [SystemVerilogCustomDefinitionSynthesisResult] for the given
  /// [module].
  SystemVerilogCustomDefinitionSynthesisResult(
    super.module,
    super.getInstanceTypeOfModule,
  ) : assert(
          module is SystemVerilog &&
              module.generatedDefinitionType == DefinitionGenerationType.custom,
          'This should only be used for custom system verilog definitions.',
        );

  @override
  int get matchHashCode =>
      (module as SystemVerilog).definitionVerilog('*PLACEHOLDER*')!.hashCode;

  @override
  bool matchesImplementation(SynthesisResult other) =>
      other is SystemVerilogCustomDefinitionSynthesisResult &&
      (module as SystemVerilog).definitionVerilog('*PLACEHOLDER*')! ==
          (other.module as SystemVerilog).definitionVerilog('*PLACEHOLDER*')!;

  @override
  String toFileContents() => (module as SystemVerilog).definitionVerilog(
        getInstanceTypeOfModule(module),
      )!;

  @override
  List<SynthFileContents> toSynthFileContents() => List.unmodifiable([
        SynthFileContents(
          name: instanceTypeName,
          contents: (module as SystemVerilog).definitionVerilog(
            getInstanceTypeOfModule(module),
          )!,
        ),
      ]);
}

/// A [SynthesisResult] representing a conversion of a [Module] to
/// SystemVerilog.
class SystemVerilogSynthesisResult extends SynthesisResult {
  /// Configuration controlling generated SystemVerilog.
  final SystemVerilogSynthesizerConfiguration configuration;

  /// A cached copy of the generated ports.
  late final String _portsString;

  /// A cached copy of the generated contents of the module.
  late final String _moduleContentsString;

  /// A cached copy of the generated parameters.
  late final String? _parameterString;

  /// The main [SynthModuleDefinition] for this.
  final SynthModuleDefinition _synthModuleDefinition;

  @override
  List<Module> get supportingModules =>
      _synthModuleDefinition.supportingModules;

  /// Creates a new [SystemVerilogSynthesisResult] for the given [module].
  SystemVerilogSynthesisResult(
    super.module,
    super.getInstanceTypeOfModule, {
    this.configuration = const SystemVerilogSynthesizerConfiguration(),
    bool embedSourceTraceComments = true,
  }) : _synthModuleDefinition = SystemVerilogSynthModuleDefinition(module) {
    _traceHelper = _SvTraceHelper(
      module,
      _synthModuleDefinition,
      embedSourceTraceComments: embedSourceTraceComments,
    );
    _portsString = _verilogPorts();
    _moduleContentsString = _verilogModuleContents(getInstanceTypeOfModule);
    _parameterString = _verilogParameters(module);
  }

  /// Trace-comment helper (null-safe when tracing is disabled).
  late final _SvTraceHelper _traceHelper;

  @override
  bool matchesImplementation(SynthesisResult other) =>
      other is SystemVerilogSynthesisResult &&
      other._portsString == _portsString &&
      other._parameterString == _parameterString &&
      other._moduleContentsString == _moduleContentsString;

  @override
  int get matchHashCode =>
      _portsString.hashCode ^
      _moduleContentsString.hashCode ^
      _parameterString.hashCode;

  @override
  String toFileContents() => _toVerilog();

  @override
  List<SynthFileContents> toSynthFileContents() => List.unmodifiable([
        SynthFileContents(
          name: instanceTypeName,
          description: 'SystemVerilog module definition for $instanceTypeName',
          contents: _toVerilog(),
        ),
      ]);

  /// Representation of all input port declarations in generated SV.
  Iterable<String> _verilogInputs() => _synthModuleDefinition.inputs.map((sig) {
        assert(
          module.tryInput(sig.name) != null,
          'Named input ${sig.name} not found in module ${module.name}.',
        );
        return _verilogPort('input', 'wire', configuration.inputPortType, sig);
      });

  /// Representation of all output port declarations in generated SV.
  Iterable<String> _verilogOutputs() =>
      _synthModuleDefinition.outputs.map((sig) {
        assert(
          module.tryOutput(sig.name) != null,
          'Named output ${sig.name} not found in module ${module.name}.',
        );
        return _verilogPort('output', 'var', configuration.outputPortType, sig);
      });

  /// Representation of all inout port declarations in generated SV.
  Iterable<String> _verilogInOuts() => _synthModuleDefinition.inOuts.map((sig) {
        assert(
          module.tryInOut(sig.name) != null,
          'Named inOut ${sig.name} not found in module ${module.name}.',
        );
        return _verilogPort('inout', 'wire', configuration.inOutPortType, sig);
      });

  /// The set of [SynthLogic] names that are destinations of `assign`
  /// statements.  Populated by [_verilogAssignments] so that
  /// [_verilogInternalSignals] can defer trace comments to the assignment.
  late final Set<String> _assignedSignalNames =
      _synthModuleDefinition.assignments.map((a) => a.dst.name).toSet();

  /// Representation of a port declaration in generated SV.
  String _verilogPort(
    String direction,
    String objectType,
    SystemVerilogPortTypeConfiguration portType,
    SynthLogic sig,
  ) =>
      [
        direction,
        if (portType.objectType == SystemVerilogPortType.explicit) objectType,
        if (portType.dataType == SystemVerilogPortType.explicit) 'logic',
        sig.definitionName(),
      ].join(' ');

  /// Representation of all internal net declarations in generated SV.
  String _verilogInternalSignals() {
    final declarations = <String>[];
    for (final sig in _synthModuleDefinition.internalSignals
        .where((e) => e.needsDeclaration)
        .sorted((a, b) => a.name.compareTo(b.name))) {
      // Prefer placing the trace on the first assignment rather than
      // the declaration — the assignment is the more meaningful location
      // for internal signals.  Signals with no assignment keep their
      // trace on the declaration.
      final comment = _assignedSignalNames.contains(sig.name)
          ? ''
          : _traceHelper.signalComment(sig);
      final decl = '${sig.definitionType()} ${sig.definitionName()};';
      declarations.add(_SvTraceHelper._pad(decl, comment));
    }
    return declarations.join('\n');
  }

  /// Representation of all assignments in generated SV.
  String _verilogAssignments() {
    final assignmentLines = <String>[];
    // Track which dst signals have already received a trace comment so
    // that only the *first* assignment for each signal is annotated.
    final tracedDsts = <String>{};

    String rangeString(int upperIndex, int lowerIndex) =>
        upperIndex == lowerIndex
            ? '[$upperIndex]'
            : '[$upperIndex:$lowerIndex]';

    for (final assignment in _synthModuleDefinition.assignments) {
      assert(
        !(assignment.src.isNet && assignment.dst.isNet),
        'Net connections should have been implemented as'
        ' bidirectional net connections.',
      );

      var dstSliceString = '';
      var srcSliceString = '';
      if (assignment is RangeSynthAssignment) {
        dstSliceString = rangeString(
          assignment.dstUpperIndex,
          assignment.dstLowerIndex,
        );
        srcSliceString = rangeString(
          assignment.srcUpperIndex,
          assignment.srcLowerIndex,
        );
      } else if (assignment is PartialSynthAssignment && assignment.width > 1) {
        dstSliceString = rangeString(
          assignment.dstUpperIndex,
          assignment.dstLowerIndex,
        );
      }

      final line = 'assign ${assignment.dst.name}$dstSliceString'
          ' = ${assignment.src.name}$srcSliceString;';

      // Emit the trace comment on the first assignment to this signal.
      final comment = tracedDsts.add(assignment.dst.name)
          ? _traceHelper.signalComment(assignment.dst)
          : '';

      assignmentLines.add(_SvTraceHelper._pad(line, comment));
    }
    return assignmentLines.join('\n');
  }

  /// Representation of all sub-module instantiations in generated SV.
  String _verilogSubModuleInstantiations(
    String Function(Module module) getInstanceTypeOfModule,
  ) {
    final subModuleLines = <String>[];
    for (final subModuleInstantiation
        in _synthModuleDefinition.subModuleInstantiations) {
      final instanceType = getInstanceTypeOfModule(
        subModuleInstantiation.module,
      );

      subModuleInstantiation as SystemVerilogSynthSubModuleInstantiation;

      final instantiationVerilog = subModuleInstantiation.instantiationVerilog(
        instanceType,
      );
      if (instantiationVerilog != null) {
        final comment = _traceHelper.moduleComment(
          subModuleInstantiation.module,
        );
        if (comment.isNotEmpty && instantiationVerilog.contains('\n')) {
          // Multi-line block (e.g. always_comb/always_ff): put trace on
          // the name-comment line rather than dangling after `end`.
          final firstNl = instantiationVerilog.indexOf('\n');
          final nameLine = instantiationVerilog.substring(0, firstNl);
          subModuleLines.add(
            '${_SvTraceHelper._pad(nameLine, comment)}'
            '${instantiationVerilog.substring(firstNl)}',
          );
        } else {
          subModuleLines.add(
            _SvTraceHelper._pad(instantiationVerilog, comment),
          );
        }
      }
    }
    return subModuleLines.join('\n');
  }

  /// The contents of this module converted to SystemVerilog without module
  /// declaration, ports, etc.
  String _verilogModuleContents(
    String Function(Module module) getInstanceTypeOfModule,
  ) {
    // Generate body parts first so the trace helper's file table is populated.
    final body = [
      _verilogInternalSignals(),
      _verilogAssignments(), // order matters!
      _verilogSubModuleInstantiations(getInstanceTypeOfModule),
    ].where((element) => element.isNotEmpty);

    // Prepend the file index comment (empty when no traces exist).
    return [
      _traceHelper.fileIndexComment(),
      ...body,
    ].where((element) => element.isNotEmpty).join('\n');
  }

  /// The representation of all port declarations.
  String _verilogPorts() => [
        ..._verilogInputs(),
        ..._verilogOutputs(),
        ..._verilogInOuts(),
      ].join(',\n');

  String? _verilogParameters(Module module) {
    if (module is SystemVerilog) {
      final defParams = module.definitionParameters;
      if (defParams == null || defParams.isEmpty) {
        return null;
      }

      return [
        '#(',
        defParams
            .map((p) => 'parameter ${p.type} ${p.name} = ${p.defaultValue}')
            .join(',\n'),
        ')',
      ].join('\n');
    }

    return null;
  }

  /// SV line map: signal/instance name → list of `'line:col'` positions
  /// in the generated SV output (both 1-based).
  ///
  /// Populated by [_toVerilog] when [SourceTracer.hasTraces] is `true`.
  /// Keys match the names used in the FLC trace data: [Logic.name] for
  /// signals and [Module.uniqueInstanceName] for submodule instances.
  ///
  /// The first entry is the declaration line; subsequent entries are
  /// each assignment LHS recorded in textual (source) order.
  @override
  Map<String, List<String>> get svLineMap => Map.unmodifiable(
        _svLineMap.map((k, v) => MapEntry(k, List<String>.unmodifiable(v))),
      );
  final Map<String, List<String>> _svLineMap = {};

  /// The full SV representation of this module.
  ///
  /// When tracing is active, also populates [_svLineMap] with the 1-based
  /// line numbers of every port, internal signal, assignment destination,
  /// and submodule instantiation.
  String _toVerilog() {
    final verilogModuleName = getInstanceTypeOfModule(module);
    final text = [
      ['module $verilogModuleName', _parameterString, '('].nonNulls.join(' '),
      _portsString,
      ');',
      _moduleContentsString,
      'endmodule : $verilogModuleName',
    ].join('\n');

    if (SourceTracer.hasTraces) {
      _buildSvLineMap(text);
    }

    return text;
  }

  /// Walks the already-generated [svText] counting newlines, and calls
  /// `record()` at each symbol position to build [_svLineMap].
  ///
  /// The approach: split the text into lines, then walk the same data
  /// structures used during generation to identify which line corresponds
  /// to each symbol.  Because the text is already final, this is immune
  /// to formatting changes — the tracker simply counts `\n` in the actual
  /// output.
  void _buildSvLineMap(String svText) {
    _svLineMap.clear();

    final lines = svText.split('\n');
    // We'll scan forward through `lines` matching each symbol.
    var lineIdx = 0; // 0-based index into `lines`

    /// Advance to the next line whose text contains [fragment] and record
    /// [name] at that 1-based `'line:col'` position.  Returns true if found.
    ///
    /// When [append] is true, the new position is appended to [name]'s
    /// list (used for assignment LHS lines). Without [append], the
    /// position is only recorded as the declaration entry the first
    /// time [name] is seen.
    bool scanAndRecord(String name, String fragment, {bool append = false}) {
      final nameRe = RegExp(r'\b' + RegExp.escape(name) + r'\b');
      for (var i = lineIdx; i < lines.length; i++) {
        if (lines[i].contains(fragment)) {
          lineIdx = i + 1; // advance past this line for the next search
          final nameMatch = nameRe.firstMatch(lines[i]);
          final col = nameMatch != null ? nameMatch.start + 1 : 1; // 1-based
          final pos = '${i + 1}:$col';
          final list = _svLineMap[name];
          if (list == null) {
            _svLineMap[name] = [pos];
          } else if (append && !list.contains(pos)) {
            list.add(pos);
          }
          return true;
        }
      }
      return false;
    }

    // Ports — scan for each port's definition text.
    for (final sig in _synthModuleDefinition.inputs) {
      scanAndRecord(sig.name, sig.definitionName());
    }
    for (final sig in _synthModuleDefinition.outputs) {
      scanAndRecord(sig.name, sig.definitionName());
    }
    for (final sig in _synthModuleDefinition.inOuts) {
      scanAndRecord(sig.name, sig.definitionName());
    }

    // Reset scan position past the ports for body scanning.
    // Find the ');' line that ends the port list.
    for (var i = lineIdx; i < lines.length; i++) {
      if (lines[i].trim() == ');') {
        lineIdx = i + 1;
        break;
      }
    }

    // Internal signals — sorted by name (matches generation order).
    for (final sig in _synthModuleDefinition.internalSignals
        .where((e) => e.needsDeclaration)
        .sorted((a, b) => a.name.compareTo(b.name))) {
      scanAndRecord(sig.name, sig.definitionName());
    }

    // Assignments — scan for 'assign <dst.name>'.
    // Append assignment positions so cross-probing can offer each.
    for (final assignment in _synthModuleDefinition.assignments) {
      scanAndRecord(
        assignment.dst.name,
        'assign ${assignment.dst.name}',
        append: true,
      );
    }

    // Sub-module instantiations
    //
    // Inline modules (BusSubset, Swizzle, gates, etc.) produce `assign`
    // statements as their "instantiation" verilog.  Sequential/combinational
    // modules produce `always_ff`/`always_comb` blocks.  In all cases we
    // record the destination signal name(s) so cross-probing lands on the
    // assignment rather than the declaration.
    final assignRe = RegExp(r'^assign\s+(\w+)');
    final alwaysLhsRe = RegExp(r'^\s+(\w+)\s*<=\s');
    final combLhsRe = RegExp(r'^\s+(\w+)\s*=\s');
    final singleLineFFRe = RegExp(r'always_ff\s+@\([^)]+\)\s+.*?(\w+)\s*<=');
    for (final smi in _synthModuleDefinition.subModuleInstantiations) {
      final instanceType = getInstanceTypeOfModule(smi.module);
      smi as SystemVerilogSynthSubModuleInstantiation;
      final outputPortColumns = <String, int>{};
      final sv = smi.instantiationVerilog(
        instanceType,
        outputPortColumns: outputPortColumns,
      );
      if (sv != null) {
        // Save scan position before this instantiation.
        final preInstIdx = lineIdx;

        // Record the instance itself.
        final firstLine =
            sv.contains('\n') ? sv.substring(0, sv.indexOf('\n')) : sv;
        scanAndRecord(smi.module.uniqueInstanceName, firstLine, append: true);
        final postInstIdx = lineIdx;

        // For proper module instantiations (not inline), record output
        // port connections at the instance line so cross-probing lands on
        // the instantiation rather than the wire declaration.
        // Column positions were computed during string construction.
        if (smi.module is! InlineSystemVerilog) {
          final instEntries = _svLineMap[smi.module.uniqueInstanceName];
          if (instEntries != null && instEntries.isNotEmpty) {
            // Use the declaration (first) entry as the canonical instance
            // line for output-port wiring records.
            final instEntry = instEntries.first;
            final instLine = int.parse(
              instEntry.substring(0, instEntry.indexOf(':')),
            );
            for (final outputEntry in smi.outputMapping.entries) {
              final synthLogic = outputEntry.value;
              if (synthLogic.declarationCleared ||
                  synthLogic.replacement != null) {
                continue;
              }
              final wireName = synthLogic.name;
              if (wireName != smi.module.uniqueInstanceName) {
                final col = outputPortColumns[wireName] ?? 1;
                final pos = '$instLine:$col';
                final list = _svLineMap[wireName];
                if (list == null) {
                  _svLineMap[wireName] = [pos];
                } else if (!list.contains(pos)) {
                  list.add(pos);
                }
              }
            }
          }
        }

        // Detect destination signals and record with overwrite so
        // cross-probing points to the assignment, not the declaration.
        final svLines = sv.split('\n');
        final assignMatch = assignRe.firstMatch(sv);
        if (assignMatch != null) {
          // assign X = ...
          final dstName = assignMatch.group(1)!;
          if (dstName != smi.module.uniqueInstanceName) {
            lineIdx = preInstIdx;
            scanAndRecord(dstName, 'assign $dstName', append: true);
          }
        } else if (svLines.length == 1 && singleLineFFRe.hasMatch(sv)) {
          // Single-line always_ff: always_ff @(...) ... X <= ...
          final ffMatch = singleLineFFRe.firstMatch(sv)!;
          lineIdx = preInstIdx;
          scanAndRecord(ffMatch.group(1)!, sv, append: true);
        } else if (svLines.any(
          (l) => l.startsWith('always_ff') || l.startsWith('always_comb'),
        )) {
          // Multi-line always_ff / always_comb block.
          // Scan inner lines for LHS of = or <=, recording each
          // destination at the line where its first assignment appears.
          final isFF = svLines.any((l) => l.startsWith('always_ff'));
          final lhsRe = isFF ? alwaysLhsRe : combLhsRe;
          final seen = <String>{};
          for (final svLine in svLines) {
            final m = lhsRe.firstMatch(svLine);
            if (m != null && seen.add(m.group(1)!)) {
              lineIdx = preInstIdx;
              scanAndRecord(m.group(1)!, svLine.trim(), append: true);
            }
          }
        }

        // Restore scan position past the instantiation.
        lineIdx = postInstIdx;
      }
    }
  }
}

/// Builds compact `// ROHD: f:l:c` source-trace comments for SV output.
///
/// Traces are only emitted when [SourceTracer] has recorded data.
/// The file index table is emitted once per module as a comment block;
/// each signal or instance declaration gets an inline comment referencing
/// that table.
///
/// Successive traces are delta-encoded: only the prefix that differs from
/// the previous trace is printed, since most items in a module share the
/// same parent call chain (suffix).  A bare `// ROHD: ^` means "identical
/// to the previous trace".
class _SvTraceHelper {
  final Map<String, int> _fileIndex = {};
  final List<String> _files = [];

  /// The entries from the most recently emitted trace, for delta encoding.
  List<String> _prevEntries = const [];

  /// Root directory of the current package, used to make paths relative.
  late final String _root = Directory.current.path;

  /// Whether inline `// ROHD:` comments should be emitted.
  final bool embedSourceTraceComments;

  /// The module these traces describe, used to resolve the namer's chosen
  /// source [Logic] for each net.
  final Module _module;

  /// Local trace-time mapping from synthesized nets to their source [Logic].
  final Map<SynthLogic, Logic> _sourceLogics;

  _SvTraceHelper(
    Module module,
    SynthModuleDefinition synthModuleDefinition, {
    this.embedSourceTraceComments = true,
  })  : _module = module,
        _sourceLogics = SourceTracer.synthLogicSourceMap(
          module,
          synthModuleDefinition,
        );

  /// Convert a stack-frame URI to a repo-relative path.
  String _relPath(String uri) {
    if (uri.startsWith('package:')) {
      // package:rohd/src/foo.dart → lib/src/foo.dart
      final afterPackage = uri.indexOf('/');
      if (afterPackage != -1) {
        return 'lib${uri.substring(afterPackage)}';
      }
    }
    if (uri.startsWith('file:///')) {
      final abs = uri.substring('file://'.length);
      if (abs.startsWith('$_root/')) {
        return abs.substring(_root.length + 1);
      }
      return abs;
    }
    return uri;
  }

  int _fileIdx(String uri) {
    final rel = _relPath(uri);
    return _fileIndex.putIfAbsent(rel, () {
      _files.add(rel);
      return _files.length - 1;
    });
  }

  /// Parse a pre-stringified stack trace into a list of compact `f:l:c`
  /// entry strings.
  List<String> _parseEntries(String traceString) {
    final lines = traceString.split('\n');
    final entries = <String>[];
    for (final line in lines) {
      final match = SourceTracer.frameRe.firstMatch(line);
      if (match == null) {
        continue;
      }
      final uri = match.group(2)!;
      if (SourceTracer.defaultSkipPatterns.any(uri.contains)) {
        continue;
      }
      final lineNo = match.group(3)!;
      final colNo = match.group(4);
      final idx = _fileIdx(uri);
      entries.add(colNo != null ? '$idx:$lineNo:$colNo' : '$idx:$lineNo');
    }
    return entries;
  }

  /// Format one [StackTrace] into a delta-encoded `// ROHD:` comment.
  ///
  /// Uses two levels of compression against [_prevEntries]:
  /// - **Suffix**: a common tail is stripped and a `| <joinFrame>` marker
  ///   shows where the current trace rejoins the previous one.
  /// - **Prefix**: a common head is replaced by `^N` where *N* is the
  ///   number of leading entries taken from the previous trace.
  /// - `^` alone means the entire trace is identical to the previous one.
  String _formatTrace(String traceString) {
    final entries = _parseEntries(traceString);
    if (entries.isEmpty) {
      return '';
    }

    // Find the longest common suffix between entries and _prevEntries.
    var suffixLen = 0;
    var ei = entries.length - 1;
    var pi = _prevEntries.length - 1;
    while (ei >= 0 && pi >= 0 && entries[ei] == _prevEntries[pi]) {
      suffixLen++;
      ei--;
      pi--;
    }

    if (suffixLen == entries.length) {
      _prevEntries = entries;
      return ' // ROHD: ^';
    }

    // Find the longest common prefix, not overlapping the suffix region.
    final maxPrefixCurr = entries.length - suffixLen;
    final maxPrefixPrev = _prevEntries.length - suffixLen;
    var prefixLen = 0;
    while (prefixLen < maxPrefixCurr &&
        prefixLen < maxPrefixPrev &&
        entries[prefixLen] == _prevEntries[prefixLen]) {
      prefixLen++;
    }

    _prevEntries = entries;

    final middle = entries.sublist(prefixLen, entries.length - suffixLen);
    final parts = <String>[];

    if (prefixLen > 0) {
      parts.add('^$prefixLen');
    }
    parts.addAll(middle);
    if (suffixLen > 0) {
      final joinFrame = entries[entries.length - suffixLen];
      parts
        ..add('|')
        ..add(joinFrame);
    }

    return ' // ROHD: ${parts.join(' ')}';
  }

  /// Returns an inline trace comment for a [SynthLogic], or empty string.
  String signalComment(SynthLogic synthLogic) {
    if (!SourceTracer.hasTraces || !embedSourceTraceComments) {
      return '';
    }
    final trace = SourceTracer.synthLogicTrace(
      _module,
      synthLogic,
      sourceLogics: _sourceLogics,
    );
    return trace != null ? _formatTrace(trace) : '';
  }

  /// Returns an inline trace comment for a sub-[Module], or empty string.
  String moduleComment(Module subModule) {
    if (!SourceTracer.hasTraces || !embedSourceTraceComments) {
      return '';
    }
    final trace = SourceTracer.moduleTrace(subModule);
    if (trace != null) {
      return _formatTrace(trace);
    }
    return '';
  }

  /// The minimum column at which `// ROHD:` comments should start.
  static const int _minCommentCol = 30;

  /// Pads [code] with spaces so that the appended [comment] starts at
  /// at least column [_minCommentCol].
  static String _pad(String code, String comment) {
    if (comment.isEmpty) {
      return code;
    }
    final pad = _minCommentCol - code.length;
    if (pad > 0) {
      return '$code${' ' * pad}$comment';
    }
    return '$code$comment';
  }

  /// Returns a comment block listing the file index, or empty string.
  ///
  /// Must be called after all signals/instances have been processed
  /// so that the file table is complete.  In practice this works because
  /// `_verilogModuleContents` calls signal/instantiation generators
  /// first, then prepends this result.
  String fileIndexComment() {
    if (_files.isEmpty) {
      return '';
    }
    final lines = <String>['// Source files:'];
    for (var i = 0; i < _files.length; i++) {
      lines.add('//   $i: ${_files[i]}');
    }
    return lines.join('\n');
  }
}
