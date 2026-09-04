// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// module_service.dart
// Common base types shared by all module-scoped services.
//
// 2026 June 23
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async';

import 'package:rohd/rohd.dart';

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

/// A named artifact produced by an [ArtifactProducingService].
///
/// Artifacts expose their content as bytes so services can retain data in
/// memory, generate it lazily, or stream it without requiring a filesystem.
class ModuleServiceArtifact {
  /// Creates an artifact with [fileName], [mediaType], and byte [openRead].
  const ModuleServiceArtifact({
    required this.fileName,
    required this.mediaType,
    required Stream<List<int>> Function() openRead,
  }) : _openRead = openRead;

  /// The artifact filename, including its format-specific extension.
  final String fileName;

  /// The IANA-style media type of the artifact.
  final String mediaType;

  final Stream<List<int>> Function() _openRead;

  /// Opens a new stream of the artifact's bytes.
  Stream<List<int>> openRead() => _openRead();
}

/// A [ModuleService] that produces named output artifacts.
///
/// The output location is always a directory. [outputBaseName] defaults to the
/// module definition name, while each concrete service configuration determines
/// artifact extensions and layouts.
abstract class ArtifactProducingService implements ModuleService {
  /// Creates an artifact-producing service for [module].
  ArtifactProducingService(
    this.module, {
    this.outputDirectory = '.',
    String? outputBaseName,
  }) : outputBaseName = outputBaseName ?? module.definitionName;

  /// The top-level [Module] this service operates on.
  @override
  final Module module;

  /// Directory receiving filesystem artifacts when this service writes them.
  final String outputDirectory;

  /// Filename stem used for primary artifacts.
  final String outputBaseName;

  /// The artifacts this service can provide.
  Iterable<ModuleServiceArtifact> get artifacts;
}

/// An [ArtifactProducingService] that generates source-code text.
///
/// Shared by language code-generation services, which all produce a combined
/// single-file [output].
abstract class CodeGenService extends ArtifactProducingService {
  /// Creates a code-generation service for [module].
  CodeGenService(
    super.module, {
    super.outputDirectory,
    super.outputBaseName,
  });

  /// The combined single-file generated output (including any header).
  String get output;
}
