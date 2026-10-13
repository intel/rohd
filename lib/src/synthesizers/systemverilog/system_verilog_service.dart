// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// system_verilog_service.dart
// Service wrapper for SystemVerilog synthesis.
//
// 2026 April 25
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:convert';
import 'dart:io';

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/systemverilog/systemverilog_synthesis_result.dart';
import 'package:rohd/src/utilities/config.dart';
import 'package:rohd/src/utilities/timestamper.dart';

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
/// final sv = SystemVerilogService(
///   dut,
///   outputDirectory: 'build',
///   multiFile: true,
/// );
///
/// // Write individual .sv files:
/// sv.writeOutputs();
///
/// // Or get the concatenated output:
/// print(sv.output);
/// ```
class SystemVerilogService extends CodeGenService {
  /// The most recently registered [SystemVerilogService], or `null`.
  ///
  /// This is backed by [ModuleServices], so it is cleared by unregistering
  /// this service type or resetting the registry.
  static SystemVerilogService? get current =>
      ModuleServices.instance.lookup<SystemVerilogService>();

  /// The separator inserted between module definitions in the
  /// concatenated single-file output from [allContents].
  ///
  /// Matches the historical single-file synthesis output format.
  static const moduleSeparator = '\n\n////////////////////\n\n';

  /// Whether the artifact layout emits one `.sv` file per module definition
  /// (`true`) or a single concatenated file (`false`).
  final bool multiFile;

  /// Whether generated SV files include the ROHD generation header.
  ///
  /// Defaults to `true` for single-file output and `false` for multi-file
  /// output, preserving the historical layout. Set explicitly to select any
  /// combination of header and file layout.
  final bool includeHeader;

  /// Configuration controlling generated SystemVerilog.
  final SystemVerilogSynthesizerConfiguration configuration;

  /// The underlying [SynthBuilder] that drove synthesis.
  late final SynthBuilder synthBuilder;

  /// The generated file contents (one per unique module definition).
  late final List<SynthFileContents> fileContents;

  /// Creates a [SystemVerilogService] for [module].
  ///
  /// [module] must already be built.
  ///
  /// [outputDirectory] defaults to the current directory and [outputBaseName]
  /// defaults to [Module.definitionName]. [includeHeader] defaults to
  /// `!multiFile` to preserve the historical layout. Set [register] to `false`
  /// to keep this service out of [ModuleServices].
  SystemVerilogService(
    Module module, {
    super.outputDirectory,
    super.outputBaseName,
    this.multiFile = false,
    bool? includeHeader,
    this.configuration = const SystemVerilogSynthesizerConfiguration(),
    bool register = true,
  })  : includeHeader = includeHeader ?? !multiFile,
        super(module) {
    if (!module.hasBuilt) {
      throw ModuleNotBuiltException(module);
    }

    synthBuilder = SynthBuilder(
        module, SystemVerilogSynthesizer(configuration: configuration));
    fileContents = synthBuilder.getSynthFileContents();

    if (register) {
      ModuleServices.instance.register<SystemVerilogService>(this);
    }
  }

  /// Backwards-compatible alias for [output].
  String get synthOutput => output;

  /// The file path used for single-file output.
  String get outputPath =>
      multiFile ? outputDirectory : '$outputDirectory/$outputBaseName.sv';

  /// Number of newlines in [moduleSeparator].
  static final int _separatorNewlines = '\n'.allMatches(moduleSeparator).length;

  /// The number of newlines in the emitted [header].
  int get headerLineCount => '\n'.allMatches(header).length;

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
  /// [instanceTypeLineOffsets] or [singleFileSvLineMapsByModule].
  late final Map<String, int> moduleLineOffsets = Map.unmodifiable({
    for (final result in synthesisResults)
      if (instanceTypeLineOffsets.containsKey(result.instanceTypeName))
        result.module.definitionName:
            instanceTypeLineOffsets[result.instanceTypeName],
  });

  /// Returns per-module SystemVerilog line maps keyed by generated
  /// implementation name.
  ///
  /// Positions include the file-local [header] offset when enabled.
  Map<String, Map<String, List<String>>> get perModuleSvLineMaps => {
        for (final result
            in synthesisResults.whereType<SystemVerilogSynthesisResult>())
          result.instanceTypeName: {
            for (final entry in result.svLineMap.entries)
              entry.key: [
                for (final position in entry.value)
                  _offsetLineCol(position, headerLineCount),
              ],
          },
      };

  /// Returns per-source-module line maps for the generated implementation
  /// associated with each occurrence.
  ///
  /// Equivalent source occurrences intentionally share the same map.
  Map<Module, Map<String, List<String>>> get perModuleSvLineMapsByModule =>
      _lineMapsByModule(perModuleSvLineMaps);

  /// Returns line maps adjusted to positions within single-file [output],
  /// keyed by generated implementation name.
  Map<String, Map<String, List<String>>> get singleFileSvLineMaps => {
        for (final result
            in synthesisResults.whereType<SystemVerilogSynthesisResult>())
          result.instanceTypeName: {
            for (final entry in result.svLineMap.entries)
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
  Map<Module, Map<String, List<String>>> get singleFileSvLineMapsByModule =>
      _lineMapsByModule(singleFileSvLineMaps);

  Map<Module, Map<String, List<String>>> _lineMapsByModule(
    Map<String, Map<String, List<String>>> lineMapsByInstanceType,
  ) {
    final result = Map<Module, Map<String, List<String>>>.identity();
    for (final entry in synthBuilder.moduleInstanceTypes.entries) {
      final lineMap = lineMapsByInstanceType[entry.value];
      if (lineMap != null) {
        result[entry.key] = lineMap;
      }
    }
    return result;
  }

  /// Maps generated implementation names to their split-file artifacts.
  Map<String, String> get svFileMapByInstanceType => {
        for (final fileContent in fileContents)
          fileContent.name: '${fileContent.name}.sv',
      };

  /// Maps each source module occurrence to its split-file artifact.
  ///
  /// Equivalent source occurrences intentionally map to the same artifact.
  Map<Module, String> get svFileMapByModule {
    final result = Map<Module, String>.identity();
    final filesByInstanceType = svFileMapByInstanceType;
    for (final entry in synthBuilder.moduleInstanceTypes.entries) {
      final file = filesByInstanceType[entry.value];
      if (file != null) {
        result[entry.key] = file;
      }
    }
    return result;
  }

  /// Maps each source module occurrence to [filename] for a concatenated
  /// single-file artifact.
  Map<Module, String> singleFileSvFileMapByModule(String filename) {
    final result = Map<Module, String>.identity();
    final filesByInstanceType = svFileMapByInstanceType;
    for (final entry in synthBuilder.moduleInstanceTypes.entries) {
      if (filesByInstanceType.containsKey(entry.value)) {
        result[entry.key] = filename;
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

  /// Writes concatenated output to [path], or to [outputPath] when omitted.
  void write([String? path]) {
    final target = path ?? outputPath;
    if (multiFile) {
      writeFiles(target);
    } else {
      final file = File(target);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(output);
    }
  }

  /// Writes each generated module to its own file.
  void writeFiles([String? directory]) {
    final targetDirectory = directory ?? outputDirectory;
    Directory(targetDirectory).createSync(recursive: true);
    for (final fileContent in fileContents) {
      File('$targetDirectory/${fileContent.name}.sv')
          .writeAsStringSync(header + fileContent.contents);
    }
  }

  /// All [SynthesisResult]s produced by synthesis.
  Set<SynthesisResult> get synthesisResults => synthBuilder.synthesisResults;

  /// Returns the concatenated SystemVerilog module definitions as a single
  /// string, without the generation header.
  ///
  /// For the full output with header (matching [Module.dumpSystemVerilog]),
  /// use [output].
  String get allContents =>
      fileContents.map((fc) => fc.contents).join(moduleSeparator);

  /// The ROHD generation header prepended to single-file output.
  String get synthHeader => '''
/**
 * Generated by ROHD - www.github.com/intel/rohd
 * Generation time: ${Timestamper.stamp()}
 * ROHD Version: ${Config.version}
 */

''';

  /// The generation header included in each emitted SV file, when enabled.
  ///
  /// Cached so output and emitted files always use the same timestamp.
  late final String header = includeHeader ? synthHeader : '';

  /// Returns the full single-file SystemVerilog output with header,
  /// identical to [Module.dumpSystemVerilog].
  ///
  /// Computed once and cached so the timestamped header is stable for the
  /// lifetime of this service.
  @override
  late final String output = header + allContents;

  /// Returns generated SV contents keyed by original module definition name.
  Map<String, String> get contentsByDefinitionName {
    final result = <String, String>{};
    for (final synthesisResult in synthesisResults) {
      final definitionName = synthesisResult.module.definitionName;
      final instanceTypeName = synthesisResult.instanceTypeName;
      for (final fileContent in fileContents) {
        if (fileContent.name == instanceTypeName) {
          result[definitionName] = fileContent.contents;
          break;
        }
      }
    }
    return result;
  }

  /// Returns SV output for a generated module [instanceTypeName], or `null`
  /// when that instance type was not generated.
  ///
  /// The instance type name is [SynthesisResult.instanceTypeName], the
  /// uniquified definition name used in the generated SV.
  String? instanceTypeOutput(String instanceTypeName) {
    for (final fc in fileContents) {
      if (fc.name == instanceTypeName) {
        return fc.contents;
      }
    }
    return null;
  }

  /// Returns a map from generated module instance type name to its SV contents.
  ///
  /// Keys are [SynthesisResult.instanceTypeName] (the uniquified definition
  /// name used in the generated SV).
  @Deprecated('Use instanceTypeOutput(instanceTypeName) for lookup or '
      'fileContents for iteration instead.')
  Map<String, String> get contentsByName => {
        for (final fc in fileContents) fc.name: fc.contents,
      };

  /// The artifacts generated by this service.
  ///
  /// Single-file output is named `<outputBaseName>.sv`. Split output retains
  /// the generated definition names so module references remain obvious.
  @override
  Iterable<ModuleServiceArtifact> get artifacts => multiFile
      ? [
          for (final fc in fileContents)
            ModuleServiceArtifact(
              fileName: '${fc.name}.sv',
              mediaType: 'text/x-systemverilog',
              openRead: () => Stream.value(utf8.encode(header + fc.contents)),
            ),
        ]
      : [
          ModuleServiceArtifact(
            fileName: '$outputBaseName.sv',
            mediaType: 'text/x-systemverilog',
            openRead: () => Stream.value(utf8.encode(output)),
          ),
        ];

  /// Writes this service's artifacts to [outputDirectory].
  void writeOutputs() {
    final directory = Directory(outputDirectory)..createSync(recursive: true);
    if (multiFile) {
      for (final fc in fileContents) {
        File('${directory.path}/${fc.name}.sv')
            .writeAsStringSync(header + fc.contents);
      }
    } else {
      File('${directory.path}/$outputBaseName.sv').writeAsStringSync(output);
    }
  }

  /// Writes the single-file output to an exact legacy [outputPath].
  ///
  /// This preserves the legacy convenience API's arbitrary filename behavior
  /// without changing the service artifact naming convention.
  void writeLegacyOutputPath(String outputPath) {
    if (multiFile) {
      throw StateError(
        'writeLegacyOutputPath is only valid for single-file output.',
      );
    }
    File(outputPath)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(output);
  }

  /// Returns a JSON-serialisable summary of the SV synthesis.
  ///
  /// Contains the list of generated module definition names.
  @override
  Map<String, Object> toJson() => <String, Object>{
        'modules': [for (final fc in fileContents) fc.name],
      };
}
