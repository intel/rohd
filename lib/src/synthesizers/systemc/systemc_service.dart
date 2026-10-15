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

  /// Map from module definition name to the list of generated SC files
  /// for that module (typically one element today; future-proof for
  /// header + impl).
  Map<String, List<String>> get scFileMap {
    final result = <String, List<String>>{};
    for (final sr in synthesisResults) {
      final defName = sr.module.definitionName;
      final instanceName = sr.instanceTypeName;
      final fc = _fileContents.firstWhereOrNull((f) => f.name == instanceName);
      if (fc != null) {
        result[defName] = ['${fc.name}.sc'];
      }
    }
    return result;
  }

  /// Map from module definition name to the list of [SystemCSynthesisResult]
  /// `scLineMap`s (signal/instance name → list of `'line:col'` positions).
  Map<String, Map<String, List<String>>> get scLineMaps => {
        for (final sr in _systemCResults)
          sr.module.definitionName: sr.scLineMap,
      };

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
