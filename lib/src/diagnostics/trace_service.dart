// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// trace_service.dart
// Service wrapper for trace-based FLC (File-Line-Column) lookup data.
//
// 2026 April 25
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:convert';
import 'dart:io';

import 'package:rohd/rohd.dart';

/// How the generated SystemVerilog is laid out on disk.
///
/// This controls whether [TraceService] emits FLC data with per-module
/// line numbers (for separate `.sv` files) or file-global line numbers
/// (for a single concatenated `.sv` file).
enum SvOutputMode {
  /// Each module definition lives in its own `.sv` file.
  ///
  /// Line numbers are 1-based within each module's SV content.
  perModule,

  /// All module definitions are concatenated into a single `.sv` file
  /// (the output of `Module.dumpSystemVerilog()`).
  ///
  /// Line numbers include the header offset so they match the
  /// concatenated output directly.
  singleFile,
}

/// How generated SystemC is laid out on disk.
enum ScOutputMode {
  /// Each module definition lives in its own `.sc` file.
  perModule,

  /// All module definitions are concatenated into one `.sc` file.
  singleFile,
}

/// A service that combines [SourceTracer] stack traces with
/// [SystemVerilogService] line maps to produce FLC (File-Line-Column)
/// cross-probing data.
///
/// FLC data maps each signal and submodule instance in the generated
/// SystemVerilog back to the Dart source location where it was constructed.
///
/// **Prerequisite:** A [SourceTracer] must be constructed *before*
/// building the module, so that construction-site stack traces are
/// captured.
///
/// Typical usage (see `tool/diagnostics/gen_filterbank_flc.dart` for a full
/// example):
///
/// ```dart
/// SourceTracer.activate();
/// final dut = MyModule(a, b);
/// await dut.build();
///
/// final sv = SystemVerilogService(dut, register: false);
/// TraceService(dut, svService: sv, register: false)
///     .write('build/output');
/// ```
///
/// Key accessors:
/// - [flcJson] — full hierarchy as a JSON string.
/// - [flcModuleJson] — single module by definition name.
/// - [flcHtml] — self-contained HTML cross-probe viewer.
/// - [write] / [writeHtml] — write JSON / HTML to a directory.
class TraceService extends ArtifactProducingService {
  /// The most recently registered [TraceService], or `null`.
  ///
  /// This is backed by [ModuleServices], so it is cleared by unregistering
  /// this service type or resetting the registry.
  static TraceService? get current =>
      ModuleServices.instance.lookup<TraceService>();

  /// The [SystemVerilogService] whose line maps enrich the FLC output.
  ///
  /// If `null`, FLC data will contain source locations only (no SV
  /// line numbers).
  final SystemVerilogService? svService;

  /// The optional [SystemCService] whose line maps enrich the FLC output.
  final SystemCService? scService;

  /// The package root directory, used to make source paths relative.
  ///
  /// Defaults to [Directory.current] path if not provided.
  final String packageRoot;

  /// The cached FLC hierarchy JSON map.
  Map<String, Object>? _flcHierarchyCache;

  /// The absolute path to the FLC file most recently written by [write].
  String? _writtenPath;

  /// Returns the path to the FLC file written by [write], or `null` if
  /// [write] has not been called.
  String? get writtenPath => _writtenPath;

  /// The default directory written by [write] when no path is supplied.
  ///
  /// FLC output is a single `<definitionName>.flc.json` file placed inside
  /// this directory.  May be `null`, in which case a path must be passed to
  /// [write].
  final String? outputPath;

  /// How the generated SV is laid out on disk.
  ///
  /// Determines whether [flcHierarchy] and [flcForModule] emit
  /// per-module or file-global SV line numbers.
  final SvOutputMode svOutputMode;

  /// How generated SystemC line numbers are interpreted.
  final ScOutputMode scOutputMode;

  /// Creates a [TraceService] for [module].
  ///
  /// [module] must already be built. If [svService] is provided, its
  /// line maps are merged into the FLC output. [outputPath] sets the
  /// default directory for [write]. Set [register] to `true`
  /// (the default) to register with [ModuleServices].
  ///
  /// [svOutputMode] controls whether FLC data uses per-module or
  /// file-global SV line numbers.
  TraceService(
    Module module, {
    this.svService,
    this.scService,
    String? packageRoot,
    this.outputPath,
    bool register = true,
    this.svOutputMode = SvOutputMode.singleFile,
    ScOutputMode? scOutputMode,
    super.outputDirectory,
    super.outputBaseName,
  })  : packageRoot = packageRoot ?? Directory.current.path,
        scOutputMode = scOutputMode ??
            (scService?.multiFile == false
                ? ScOutputMode.singleFile
                : ScOutputMode.perModule),
        super(module) {
    if (!module.hasBuilt) {
      throw ModuleNotBuiltException(module);
    }

    if (register) {
      ModuleServices.instance.register<TraceService>(this);
    }
  }

  /// The generated FLC hierarchy artifact.
  @override
  Iterable<ModuleServiceArtifact> get artifacts => [
        ModuleServiceArtifact(
          fileName: '$outputBaseName.flc.json',
          mediaType: 'application/json',
          openRead: () => Stream.value(utf8.encode(flcJson)),
        ),
      ];

  /// Whether any traces were captured during the build.
  bool get hasTraces => SourceTracer.hasTraces;

  /// Reorders collected positions from synthesizer order
  /// (declaration, assignments...) to FLC navigation order
  /// (assignments..., declaration).
  static List<String> _declarationLast(List<String> positions) =>
      positions.length <= 1
          ? List.unmodifiable(positions)
          : List.unmodifiable([...positions.skip(1), positions.first]);

  /// Applies [_declarationLast] to every symbol in a language line map.
  static Map<String, Map<String, List<String>>> _declarationsLast(
    Map<String, Map<String, List<String>>> lineMaps,
  ) =>
      {
        for (final moduleEntry in lineMaps.entries)
          moduleEntry.key: {
            for (final symbolEntry in moduleEntry.value.entries)
              symbolEntry.key: _declarationLast(symbolEntry.value),
          },
      };

  /// Applies [_declarationLast] to every source-module-associated line map.
  static Map<Module, Map<String, List<String>>> _declarationsLastByModule(
    Map<Module, Map<String, List<String>>> lineMaps,
  ) {
    final result = Map<Module, Map<String, List<String>>>.identity();
    for (final moduleEntry in lineMaps.entries) {
      result[moduleEntry.key] = {
        for (final symbolEntry in moduleEntry.value.entries)
          symbolEntry.key: _declarationLast(symbolEntry.value),
      };
    }
    return result;
  }

  // ─── SV line map helpers ──────────────────────────────────────

  /// Collects header-adjusted `svLineMaps` keyed by generated implementation
  /// name.
  ///
  /// Line numbers are per-module (1-based within each emitted module file),
  /// including a header when [SystemVerilogService.includeHeader] is `true`.
  /// Each value is a list of `"L:C"` positions (declaration + each
  /// assignment LHS, in textual order).
  Map<String, Map<String, List<String>>> get svLineMaps =>
      _declarationsLast(svService?.perModuleSvLineMaps ?? const {});

  /// Collects per-source-module SV line maps.
  ///
  /// This preserves the association from every source module occurrence to
  /// its generated implementation, including many-to-one implementation
  /// sharing.
  Map<Module, Map<String, List<String>>> get svLineMapsByModule =>
      _declarationsLastByModule(
        svService?.perModuleSvLineMapsByModule ?? const {},
      );

  /// Collects `svFileMap` (generated implementation name → `.sv` filename)
  /// from the [SystemVerilogService] file contents.
  Map<String, String> get svFileMap =>
      svService?.svFileMapByInstanceType ?? const {};

  /// Collects the emitted SV artifact for every source module occurrence.
  Map<Module, String> get svFileMapByModule =>
      svService?.svFileMapByModule ?? const {};

  // ─── Single-file helpers ─────────────────────────────────────

  /// Returns [svLineMaps] with line numbers adjusted to file-global
  /// positions within [SystemVerilogService.synthOutput].
  ///
  /// Use this when the generated SV is a single concatenated file.
  /// Line numbers include the header offset so they match
  /// [SystemVerilogService.synthOutput] (and `Module.dumpSystemVerilog()`)
  /// directly.
  Map<String, Map<String, List<String>>> get singleFileSvLineMaps =>
      _declarationsLast(svService?.singleFileSvLineMaps ?? const {});

  /// Returns source-module SV line maps with file-global line numbers.
  Map<Module, Map<String, List<String>>> get singleFileSvLineMapsByModule =>
      _declarationsLastByModule(
        svService?.singleFileSvLineMapsByModule ?? const {},
      );

  /// Returns an [svFileMap] where every module maps to [filename].
  ///
  /// Use this when all modules share a single concatenated SV file.
  Map<String, String> singleFileSvFileMap(String filename) {
    if (svService == null) {
      return const {};
    }
    return {
      for (final instanceTypeName in svService!.svFileMapByInstanceType.keys)
        instanceTypeName: filename,
    };
  }

  /// Returns a source-module SV file map where every occurrence maps to
  /// [filename].
  Map<Module, String> singleFileSvFileMapByModule(String filename) =>
      svService?.singleFileSvFileMapByModule(filename) ?? const {};

  /// The file path to advertise for single-file SV output.
  String get _singleFileSvPath {
    final path = svService?.multiFile == false ? svService?.outputPath : null;
    return path == null
        ? '${module.definitionName}.sv'
        : File(path).absolute.path;
  }

  /// The file path advertised for single-file SystemC output.
  String get _singleFileScPath {
    final service = scService;
    return service == null || service.multiFile
        ? '${module.definitionName}.sc'
        : File(
            '${service.outputDirectory}/${service.outputBaseName}.sc',
          ).absolute.path;
  }

  // ─── Mode-dependent helpers ──────────────────────────────────

  /// SV line maps selected by [svOutputMode].
  Map<Module, Map<String, List<String>>> get _activeSvLineMaps =>
      svOutputMode == SvOutputMode.singleFile
          ? singleFileSvLineMapsByModule
          : svLineMapsByModule;

  /// SV file map selected by [svOutputMode].
  Map<Module, String> get _activeSvFileMap =>
      svOutputMode == SvOutputMode.singleFile
          ? singleFileSvFileMapByModule(_singleFileSvPath)
          : svFileMapByModule;

  /// SystemC line maps selected by [scOutputMode].
  Map<Module, Map<String, List<String>>> get _activeScLineMaps {
    final service = scService;
    if (service == null) {
      return const {};
    }
    return _declarationsLastByModule(
      scOutputMode == ScOutputMode.singleFile
          ? service.singleFileScLineMapsByModule
          : service.scLineMapsByModule,
    );
  }

  /// SystemC file maps selected by [scOutputMode].
  Map<Module, List<String>> get _activeScFileMap {
    final service = scService;
    if (service == null) {
      return const {};
    }
    return scOutputMode == ScOutputMode.singleFile
        ? service.singleFileScFileMapByModule(_singleFileScPath)
        : service.scFileMapByModule;
  }

  /// Builds source-module-associated output file metadata.
  Map<Module, Map<String, List<String>>> _outputFilesFor(
    Map<Module, String> svFiles,
    Map<Module, List<String>> scFiles,
  ) {
    final result = Map<Module, Map<String, List<String>>>.identity();
    for (final e in svFiles.entries) {
      result.putIfAbsent(e.key, () => <String, List<String>>{})['sv'] = [
        e.value,
      ];
    }
    for (final e in scFiles.entries) {
      result.putIfAbsent(e.key, () => <String, List<String>>{})['sc'] = e.value;
    }
    return result;
  }

  /// Builds source-module-associated generated-code line maps.
  Map<Module, Map<String, Map<String, List<String>>>> _outputLineMapsFor(
    Map<Module, Map<String, List<String>>> svLineMaps,
    Map<Module, Map<String, List<String>>> scLineMaps,
  ) {
    final result =
        Map<Module, Map<String, Map<String, List<String>>>>.identity();
    for (final e in svLineMaps.entries) {
      result.putIfAbsent(
          e.key, () => <String, Map<String, List<String>>>{})['sv'] = e.value;
    }
    for (final e in scLineMaps.entries) {
      result.putIfAbsent(
          e.key, () => <String, Map<String, List<String>>>{})['sc'] = e.value;
    }
    return result;
  }

  Map<Module, Map<String, List<String>>> get _outputFiles =>
      _outputFilesFor(_activeSvFileMap, _activeScFileMap);

  Map<Module, Map<String, Map<String, List<String>>>> get _outputLineMaps =>
      _outputLineMapsFor(_activeSvLineMaps, _activeScLineMaps);

  /// Maps source module occurrences to their generated implementation names.
  ///
  /// SystemVerilog is preferred when both code generators are present because
  /// its implementation names are used by the primary FLC output files.
  Map<Module, String> get _moduleImplementationNames {
    final result = Map<Module, String>.identity();
    final sv = svService;
    if (sv != null) {
      result.addAll(sv.synthBuilder.moduleInstanceTypes);
    }
    final sc = scService;
    if (sc != null) {
      for (final entry in sc.moduleInstanceTypes.entries) {
        result.putIfAbsent(entry.key, () => entry.value);
      }
    }
    return result;
  }

  /// Returns the FLC hierarchy with SV line numbers adjusted for
  /// single-file concatenated output.
  ///
  /// [svFilename] is the name stored in each module's `svFile` field
  /// (e.g. `'MyTop.sv'`).
  /// Line numbers match [SystemVerilogService.synthOutput] (with header).
  ///
  /// Returns `null` if no traces were recorded.
  ///
  /// If [packageMap] is provided it is forwarded to
  /// [SourceTracer.traceJsonForHierarchy], bypassing the
  /// file-system–based `loadPackageMap` (required on web where
  /// `dart:io` is unavailable).
  Map<String, Object>? singleFileFlcHierarchy(
    String svFilename, {
    String? scFilename,
    Map<String, String>? packageMap,
  }) {
    final service = scService;
    final scLineMaps = service == null
        ? const <Module, Map<String, List<String>>>{}
        : _declarationsLastByModule(service.singleFileScLineMapsByModule);
    final scFiles = service == null
        ? const <Module, List<String>>{}
        : service.singleFileScFileMapByModule(
            scFilename ?? _singleFileScPath,
          );

    return SourceTracer.traceJsonForHierarchy(
      module,
      packageRoot: packageRoot,
      moduleOutputLineMaps: _outputLineMapsFor(
        singleFileSvLineMapsByModule,
        scLineMaps,
      ),
      moduleOutputFiles: _outputFilesFor(
        singleFileSvFileMapByModule(svFilename),
        scFiles,
      ),
      moduleImplementationNames: _moduleImplementationNames,
      packageMap: packageMap,
    );
  }

  /// Writes FLC JSON for single-file mode to [directory].
  ///
  /// Produces a single `<definitionName>.flc.json` with file-global
  /// SV line numbers matching [SystemVerilogService.synthOutput]
  /// (and `Module.dumpSystemVerilog()`).
  void writeSingleFileFlc(
    String directory, {
    String? svFilename,
    String? scFilename,
  }) {
    final name = svFilename ?? '${module.definitionName}.sv';
    final hierarchy = singleFileFlcHierarchy(name, scFilename: scFilename);
    if (hierarchy != null) {
      final dir = Directory(directory)..createSync(recursive: true);
      File('${dir.path}/${module.definitionName}.flc.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(hierarchy),
      );
    }
  }

  // ─── FLC JSON output ─────────────────────────────────────────

  /// Returns the FLC JSON map for the full module hierarchy, or `null`
  /// if no traces were recorded.
  ///
  /// Line numbers are per-module or file-global depending on
  /// [svOutputMode].
  ///
  /// The result is cached after the first call.
  Map<String, Object>? get flcHierarchy =>
      _flcHierarchyCache ??= SourceTracer.traceJsonForHierarchy(
        module,
        packageRoot: packageRoot,
        moduleOutputLineMaps: _outputLineMaps,
        moduleOutputFiles: _outputFiles,
        moduleImplementationNames: _moduleImplementationNames,
      );

  /// Returns the FLC hierarchy as a JSON string, or an unavailable status.
  String get flcJson =>
      flcHierarchy != null ? jsonEncode(flcHierarchy) : _unavailable;

  /// A JSON-serialisable view of the FLC (file-line-column) trace data.
  ///
  /// Returns the FLC hierarchy map (the same content as [flcJson]), or an
  /// `unavailable` status map when no traces or package root are available.
  @override
  Map<String, Object?> toJson() =>
      flcHierarchy ?? const <String, Object?>{'status': 'unavailable'};

  /// Returns the FLC JSON for the sole source occurrence with
  /// [definitionName], or `null` if no traces exist for that module.
  ///
  /// Throws an [ArgumentError] when more than one source occurrence requested
  /// [definitionName]. Use [flcForModuleInstance] in that case so a caller
  /// cannot accidentally cross-probe the wrong occurrence.
  Map<String, Object>? flcForModule(String definitionName) {
    final targets = <Module>[];
    void walk(Module m) {
      if (m.definitionName == definitionName) {
        targets.add(m);
      }
      m.subModules.forEach(walk);
    }

    walk(module);

    if (targets.isEmpty) {
      return null;
    }
    if (targets.length > 1) {
      throw ArgumentError.value(
        definitionName,
        'definitionName',
        'matches ${targets.length} source module occurrences; use '
            'flcForModuleInstance instead',
      );
    }

    return flcForModuleInstance(targets.single);
  }

  /// Returns FLC JSON for one exact source module occurrence, or `null` if
  /// no traces were captured for it.
  Map<String, Object>? flcForModuleInstance(Module target) =>
      SourceTracer.traceJsonForModule(
        target,
        packageRoot: packageRoot,
        moduleOutputLineMap: _outputLineMaps[target],
        moduleOutputFile: _outputFiles[target],
        implementationName: _moduleImplementationNames[target],
      );

  /// Returns the FLC JSON for a generated [implementationName] as a JSON
  /// string (v6 format).
  ///
  /// Extracts the target module's entry from the cached v6 hierarchy so the
  /// returned JSON is always in the same trie-based format as [flcJson].
  String flcModuleJson(String implementationName) {
    final hierarchy = flcHierarchy;
    if (hierarchy == null) {
      return _unavailable;
    }
    final modules = hierarchy['modules'] as Map<String, Object>?;
    if (modules == null || !modules.containsKey(implementationName)) {
      return _unavailable;
    }
    return jsonEncode(<String, Object>{
      'version': 6,
      'files': hierarchy['files']!,
      'modules': <String, Object>{
        implementationName: modules[implementationName]!,
      },
    });
  }

  /// Returns FLC JSON for the generated implementation of [sourceModule].
  String flcModuleJsonForModule(Module sourceModule) => flcModuleJson(
        _moduleImplementationNames[sourceModule] ?? sourceModule.definitionName,
      );

  // ─── HTML viewer ─────────────────────────────────────────────

  /// Returns a self-contained HTML viewer for the FLC data.
  ///
  /// Returns `null` if no traces were recorded.
  String? get flcHtml {
    final json = flcHierarchy;
    if (json == null) {
      return null;
    }
    return SourceTracer.flcHtmlViewer(
      jsonEncode(json),
      title: '${module.definitionName} FLC Viewer',
      packageRoot: packageRoot,
    );
  }

  // ─── File writing ────────────────────────────────────────────

  /// Writes the FLC JSON hierarchy file to [path] (or [outputPath]).
  ///
  /// A [path] ending in `.json` is treated as the exact output file. Other
  /// paths are treated as directories containing
  /// `<definitionName>.flc.json`. The absolute file path is recorded in
  /// [writtenPath].
  ///
  /// Throws a [StateError] if neither [path] nor [outputPath] is set.
  void write([String? path]) {
    final directory = path ?? outputPath;
    if (directory == null) {
      throw StateError(
        'No output path: pass a directory to write() or set outputPath.',
      );
    }
    final file = directory.endsWith('.json')
        ? File(directory)
        : File('$directory/${module.definitionName}.flc.json');
    file.parent.createSync(recursive: true);

    // Write the hierarchy FLC.
    final hierarchy = flcHierarchy;
    if (hierarchy != null) {
      file.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(hierarchy),
      );
      _writtenPath = file.absolute.path;
    }
  }

  /// Writes the FLC hierarchy JSON file to [directory].
  void writeFlcFiles(String directory) => write(directory);

  /// Writes the self-contained HTML viewer to [path] (or [outputPath]).
  void writeHtml([String? path]) {
    final directory = path ?? outputPath;
    if (directory == null) {
      throw StateError(
        'No output path: pass a directory to writeHtml() or set outputPath.',
      );
    }
    final html = flcHtml;
    if (html != null) {
      final dir = Directory(directory)..createSync(recursive: true);
      File('${dir.path}/${module.definitionName}.flc.html')
          .writeAsStringSync(html);
    }
  }

  /// Writes the self-contained HTML viewer to [directory].
  void writeFlcHtml(String directory) => writeHtml(directory);

  static const String _unavailable = '{"status":"unavailable",'
      '"reason":"no traces recorded"}';
}
