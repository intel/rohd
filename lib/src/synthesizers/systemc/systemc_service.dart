// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// systemc_service.dart
// Service wrapper for SystemC synthesis.
//
// 2026 May
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/systemc/systemc_synthesis_result.dart';
import 'package:rohd/src/utilities/config.dart';
import 'package:rohd/src/utilities/timestamper.dart';

/// A service that wraps SystemC synthesis of a [Module] hierarchy.
///
/// Provides access to the generated SystemC file contents and per-module
/// synthesis results.
///
/// ROHD's emitted SystemC representation uses two-state `bool`, `sc_uint`, and
/// `sc_biguint` types. It does not preserve X/Z semantics. When any bit of a
/// constant is X or Z, the emitted value for the entire constant is zero.
/// This is a limitation of ROHD's emitted representation, not SystemC itself.
class SystemCService extends CodeGenService {
  /// The most recently registered [SystemCService], or `null`.
  static SystemCService? current;

  /// Whether [writeOutputs] emits one `.sc` file per module definition
  /// (`true`) or a single concatenated file (`false`). Defaults to `true` for
  /// SystemC.
  final bool multiFile;

  /// Configuration controlling unsupported SystemC functionality.
  final SystemCSynthesizerConfiguration configuration;

  late final SystemCSynthesizer _systemCSynthesizer;

  late final SynthBuilder _synthBuilder;
  late final List<SynthFileContents> _fileContents;

  /// The generated file contents (one entry per generated SystemC file).
  List<SynthFileContents> get fileContents => _fileContents;

  /// Creates an [SystemCService] for [module].
  ///
  /// [module] must already be built.
  /// Construction does not write to the filesystem. Call [writeOutputs] to
  /// write generated artifacts to [outputDirectory].
  SystemCService(
    Module module, {
    bool register = true,
    super.outputDirectory,
    super.outputBaseName,
    this.multiFile = true,
    this.configuration = const SystemCSynthesizerConfiguration(),
  }) : super(module) {
    if (!module.hasBuilt) {
      throw Exception(
        'Module must be built before creating SystemCService. '
        'Call build() first.',
      );
    }
    _systemCSynthesizer = SystemCSynthesizer(configuration: configuration);
    _synthBuilder = SynthBuilder(module, _systemCSynthesizer);
    _fileContents = _synthBuilder.getSynthFileContents();

    if (register) {
      current = this;
      ModuleServices.instance.register<SystemCService>(this);
    }
  }

  /// The generated SystemC artifacts.
  @override
  Iterable<ModuleServiceArtifact> get artifacts => multiFile
      ? [
          for (final fileContent in _fileContents)
            ModuleServiceArtifact(
              fileName: '${fileContent.name}.sc',
              mediaType: 'text/x-systemc',
              openRead: () => Stream.value(utf8.encode(fileContent.contents)),
            ),
        ]
      : [
          ModuleServiceArtifact(
            fileName: '$outputBaseName.sc',
            mediaType: 'text/x-systemc',
            openRead: () => Stream.value(utf8.encode(output)),
          ),
        ];

  /// All [SynthesisResult]s produced by synthesis.
  Iterable<SynthesisResult> get synthesisResults =>
      _synthBuilder.synthesisResults;

  Iterable<SystemCSynthesisResult> get _systemCResults =>
      _synthBuilder.synthesisResults.whereType<SystemCSynthesisResult>();

  /// Unsupported module instances whose behavior was emitted as empty stubs.
  List<SystemCGenerationDiagnostic> get diagnostics =>
      List.unmodifiable(_systemCSynthesizer.diagnostics);

  /// Map from generated implementation name to the list of generated SC
  /// files for that implementation (typically one element today;
  /// future-proof for header + impl).
  Map<String, List<String>> get scFileMap {
    final result = <String, List<String>>{};
    for (final sr in synthesisResults) {
      final instanceName = sr.instanceTypeName;
      final fc = _fileContents.firstWhereOrNull((f) => f.name == instanceName);
      if (fc != null) {
        result[instanceName] = ['${fc.name}.sc'];
      }
    }
    return result;
  }

  /// Maps each source module occurrence to the generated SC artifact list.
  ///
  /// Equivalent source occurrences intentionally map to the same artifact.
  Map<Module, List<String>> get scFileMapByModule {
    final result = Map<Module, List<String>>.identity();
    final filesByInstanceType = scFileMap;
    for (final entry in _synthBuilder.moduleInstanceTypes.entries) {
      final files = filesByInstanceType[entry.value];
      if (files != null) {
        result[entry.key] = files;
      }
    }
    return result;
  }

  /// Map from generated implementation name to the
  /// [SystemCSynthesisResult]
  /// `scLineMap`s (signal/instance name → list of `'line:col'` positions).
  Map<String, Map<String, List<String>>> get scLineMaps => {
        for (final sr in _systemCResults)
          sr.instanceTypeName: sr.scLineMap,
      };

  /// Maps each source module occurrence to its generated SC line map.
  ///
  /// Equivalent source occurrences intentionally share the same map.
  Map<Module, Map<String, List<String>>> get scLineMapsByModule {
    final result = Map<Module, Map<String, List<String>>>.identity();
    final lineMapsByInstanceType = scLineMaps;
    for (final entry in _synthBuilder.moduleInstanceTypes.entries) {
      final lineMap = lineMapsByInstanceType[entry.value];
      if (lineMap != null) {
        result[entry.key] = lineMap;
      }
    }
    return result;
  }

  /// Map from module definition name to the generated SystemC source text.
  Map<String, String> get contentsByDefinitionName {
    final result = <String, String>{};
    for (final sr in synthesisResults) {
      final defName = sr.module.definitionName;
      final fc = _fileContents.firstWhereOrNull(
        (f) => f.name == sr.instanceTypeName,
      );
      if (fc != null) {
        result[defName] = fc.contents;
      }
    }
    return result;
  }

  /// The concatenated SystemC module definitions, without the generation
  /// header.
  String get allContents => _fileContents.map((fc) => fc.contents).join('\n');

  /// The ROHD generation header prepended to single-file SystemC output.
  String get scHeader => '// Generated by ROHD - www.github.com/intel/rohd\n'
      '// Generation time: ${Timestamper.stamp()}\n'
      '// ROHD Version: ${Config.version}\n'
      '\n'
      '#include <systemc.h>\n'
      '\n';

  /// The full single-file SystemC output with its generation header.
  ///
  /// Computed once and cached so the timestamped header is stable for the
  /// lifetime of this service.
  @override
  late final String output = scHeader + allContents;

  /// The number of newlines in [scHeader].
  int get headerLineCount => '\n'.allMatches(scHeader).length;

  /// Number of newlines inserted between generated SystemC modules.
  static const int _separatorNewlines = 1;

  /// The 0-based line offset of each generated implementation within [output].
  ///
  /// Keys are [SynthesisResult.instanceTypeName], which stays unique when
  /// multiple source modules requested the same [Module.definitionName].
  late final Map<String, int> instanceTypeLineOffsets =
      _computeInstanceTypeLineOffsets();

  Map<String, int> _computeInstanceTypeLineOffsets() {
    final offsets = <String, int>{};

    var offset = headerLineCount;
    for (var index = 0; index < fileContents.length; index++) {
      if (index > 0) {
        offset += _separatorNewlines;
      }
      offsets[fileContents[index].name] = offset;
      offset += '\n'.allMatches(fileContents[index].contents).length;
    }
    return Map.unmodifiable(offsets);
  }

  /// The 0-based line offsets keyed by requested source definition name.
  ///
  /// This legacy view cannot distinguish separately synthesized source
  /// occurrences that requested the same definition name. Prefer
  /// [instanceTypeLineOffsets] or [singleFileScLineMapsByModule].
  late final Map<String, int> moduleLineOffsets = Map.unmodifiable({
    for (final result in _systemCResults)
      if (instanceTypeLineOffsets.containsKey(result.instanceTypeName))
        result.module.definitionName:
            instanceTypeLineOffsets[result.instanceTypeName],
  });

  /// Returns SystemC line maps adjusted to positions in [output], keyed by
  /// generated implementation name.
  late final Map<String, Map<String, List<String>>> singleFileScLineMaps = {
    for (final result in _systemCResults)
      result.instanceTypeName: {
        for (final entry in result.scLineMap.entries)
          entry.key: [
            for (final position in entry.value)
              _offsetLineCol(
                position,
                instanceTypeLineOffsets[result.instanceTypeName] ?? 0,
              ),
          ],
      },
  };

  /// Returns single-file line maps for the generated implementation
  /// associated with each source module occurrence.
  Map<Module, Map<String, List<String>>> get singleFileScLineMapsByModule {
    final result = Map<Module, Map<String, List<String>>>.identity();
    for (final entry in _synthBuilder.moduleInstanceTypes.entries) {
      final lineMap = singleFileScLineMaps[entry.value];
      if (lineMap != null) {
        result[entry.key] = lineMap;
      }
    }
    return result;
  }

  /// Returns a single-file map using [filename] for every generated
  /// implementation.
  Map<String, List<String>> singleFileScFileMap(String filename) => {
        for (final result in _systemCResults)
          result.instanceTypeName: [filename],
          };

  /// Returns a single-file artifact map for every source module occurrence.
  Map<Module, List<String>> singleFileScFileMapByModule(String filename) {
    final result = Map<Module, List<String>>.identity();
    final filesByInstanceType = singleFileScFileMap(filename);
    for (final entry in _synthBuilder.moduleInstanceTypes.entries) {
      final files = filesByInstanceType[entry.value];
      if (files != null) {
        result[entry.key] = files;
      }
    }
    return result;
  }

  static String _offsetLineCol(String lineCol, int offset) {
    if (offset == 0) {
      return lineCol;
    }
    final colon = lineCol.indexOf(':');
    final line = int.parse(lineCol.substring(0, colon)) + offset;
    return '$line${lineCol.substring(colon)}';
  }

  /// Writes this service's artifacts to [outputDirectory].
  void writeOutputs() {
    final directory = Directory(outputDirectory)..createSync(recursive: true);
    if (multiFile) {
      for (final fileContent in _fileContents) {
        File('${directory.path}/${fileContent.name}.sc')
            .writeAsStringSync(fileContent.contents);
      }
    } else {
      File('${directory.path}/$outputBaseName.sc').writeAsStringSync(output);
    }
  }

  /// Returns a JSON-serialisable summary of the SystemC synthesis.
  ///
  /// Contains the list of generated module definition names.
  @override
  Map<String, Object> toJson() => <String, Object>{
        'modules': [for (final fc in _fileContents) fc.name],
      };
}
