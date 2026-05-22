// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// sv_service.dart
// Service wrapper for SystemVerilog synthesis.
//
// 2026 April 25
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:io';

import 'package:collection/collection.dart';
import 'package:rohd/rohd.dart';

/// A service that wraps SystemVerilog synthesis of a [Module] hierarchy.
///
/// Provides access to the generated SV file contents and per-module
/// synthesis results, and optionally registers with [ModuleServices]
/// for DevTools inspection.
///
/// Example:
/// ```dart
/// final dut = MyModule(...);
/// await dut.build();
/// final sv = SvService(dut);
///
/// // Write individual .sv files:
/// sv.writeFiles('build/');
///
/// // Or get the concatenated output (like generateSynth):
/// print(sv.allContents);
/// ```
class SvService {
  /// The top-level [Module] being synthesized.
  final Module module;

  /// The underlying [SynthBuilder] that drove synthesis.
  late final SynthBuilder synthBuilder;

  /// The generated file contents (one per unique module definition).
  late final List<SynthFileContents> fileContents;

  /// Creates an [SvService] for [module].
  ///
  /// [module] must already be built.  Set [register] to `true` (the
  /// default) to register this service with [ModuleServices] for
  /// DevTools access.
  SvService(this.module, {bool register = true}) {
    if (!module.hasBuilt) {
      throw Exception('Module must be built before creating SvService. '
          'Call build() first.');
    }

    synthBuilder = SynthBuilder(module, SystemVerilogSynthesizer());
    fileContents = synthBuilder.getSynthFileContents();

    if (register) {
      ModuleServices.instance.svService = this;
    }
  }

  /// All [SynthesisResult]s produced by synthesis.
  Set<SynthesisResult> get synthesisResults => synthBuilder.synthesisResults;

  /// Returns the concatenated SystemVerilog output as a single string,
  /// matching the format of [Module.generateSynth].
  String get allContents => fileContents.map((fc) => fc.contents).join('\n\n');

  /// Returns a map from module definition name to its SV file contents.
  ///
  /// Keys are [SynthesisResult.instanceTypeName] (the uniquified definition
  /// name used in the generated SV).
  Map<String, String> get contentsByName => {
        for (final fc in fileContents) fc.name: fc.contents,
      };

  /// Returns a map from module definition name
  /// ([Module.definitionName]) to its SV file contents.
  ///
  /// This uses the original definition name (not uniquified), matching
  /// the keys used by FLC trace data.
  Map<String, String> get contentsByDefinitionName {
    final result = <String, String>{};
    for (final sr in synthesisResults) {
      final defName = sr.module.definitionName;
      final instanceName = sr.instanceTypeName;
      // Find the file content matching this instance type name.
      final fc = fileContents.firstWhereOrNull((f) => f.name == instanceName);
      if (fc != null) {
        result[defName] = fc.contents;
      }
    }
    return result;
  }

  /// Writes each module's SV to a separate file in [directory].
  ///
  /// Files are named `<definitionName>.sv`.
  void writeFiles(String directory) {
    final dir = Directory(directory)..createSync(recursive: true);
    for (final fc in fileContents) {
      File('${dir.path}/${fc.name}.sv').writeAsStringSync(fc.contents);
    }
  }

  /// Returns a JSON-serialisable summary of the SV synthesis.
  ///
  /// Contains the list of generated module definition names.
  Map<String, Object> toJson() => <String, Object>{
        'modules': [
          for (final fc in fileContents) fc.name,
        ],
      };
}
