// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// module_service.dart
// Common base types shared by all module-scoped services.
//
// 2026 June 23
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';

/// The common contract implemented by every module-scoped service that
/// registers with [ModuleServices].
abstract interface class ModuleService {
  /// The top-level [Module] this service operates on.
  Module get module;

  /// A JSON-serialisable summary of this service.
  Map<String, Object?> toJson();
}

/// A [ModuleService] that emits output to one or more files.
abstract class OutputService implements ModuleService {
  /// The default location written by [write].
  String? get outputPath;

  /// Whether [write] emits one file per module definition (`true`) or a single
  /// combined file (`false`).
  bool get multiFile;

  /// Writes this service's output to [path], or to [outputPath] when [path] is
  /// omitted.
  void write([String? path]);
}

/// An [OutputService] that generates source-code text, keyed per module
/// definition.
abstract class CodeGenService extends OutputService {
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
