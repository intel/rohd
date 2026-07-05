// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// module_service.dart
// Common base types shared by all module-scoped services.
//
// 2026 June 23
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';

import 'package:rohd/src/diagnostics/output_file_writer.dart'
    if (dart.library.io) 'package:rohd/src/diagnostics/output_file_writer_io.dart';

/// The common contract implemented by every module-scoped service that
/// registers with [ModuleServices].
///
/// A service wraps some derived view of a built [Module] (synthesis output,
/// netlist, source trace, waveform, etc.) and exposes a JSON-serialisable
/// summary via [toJson].  Concrete services additionally expose their own
/// format-specific accessors; consumers reach them through
/// [ModuleServices.lookup] or the service's own `current` accessor rather than
/// through getters on the registry.
abstract interface class ModuleService {
  /// The top-level [Module] this service operates on.
  Module get module;

  /// A JSON-serialisable summary of this service.
  Map<String, Object?> toJson();
}

/// A [ModuleService] that emits output to one or more files.
///
/// Establishes the common output convention shared by synthesis, netlist,
/// trace, and waveform services:
///  - [outputPath] — the default file or directory written by [write].
///  - [multiFile] — whether [write] emits one file per module definition
///    (a directory) or a single combined file.
///  - [write] — performs the write, honouring [multiFile].
abstract class OutputService implements ModuleService {
  /// The default location written by [write].
  ///
  /// Interpreted as a directory when [multiFile] is `true`, otherwise as a
  /// single file path.  May be `null` when no default has been configured, in
  /// which case a path must be passed to [write].
  String? get outputPath;

  /// Whether [write] emits one file per module definition (`true`) or a single
  /// combined file (`false`).
  bool get multiFile;

  /// Writes this service's output to [path], or to [outputPath] when [path] is
  /// omitted.
  void write([String? path]);

  /// Writes [contents] to [path] on platforms that support file IO.
  ///
  /// Browser integrations can still construct services for in-memory output;
  /// calling write APIs there throws [UnsupportedError].
  void writeTextFile(String path, String contents) =>
      writeOutputTextFile(path, contents);
}

/// An [OutputService] that generates source-code text, keyed per module
/// definition.
///
/// Shared by the language code-generation services (e.g. SystemVerilog and
/// SystemC), which all produce a combined single-file [output] as well as
/// per-definition contents.
abstract class CodegenService extends OutputService {
  /// The combined single-file generated output (including any header).
  String get output;

  /// The generated output keyed by module definition name
  /// ([Module.definitionName]).
  Map<String, String> get contentsByDefinitionName;

  /// The generated output for a single module [definitionName], or `null` when
  /// that definition was not generated.
  String? moduleOutput(String definitionName) =>
      contentsByDefinitionName[definitionName];
}
