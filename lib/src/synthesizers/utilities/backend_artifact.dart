// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// backend_artifact.dart
// Backend-specific artifact contracts for language emission escape hatches.
//
// 2026 July
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

/// A code-generation backend that can provide a language-specific artifact.
enum EmissionBackend {
  /// SystemVerilog output.
  systemVerilog,

  /// SystemC/C++ output.
  systemC,
}

/// The emission location for a backend-specific artifact.
enum BackendArtifactKind {
  /// A complete module definition supplied by a backend-specific module.
  definition,

  /// Source injected in place of a standard module instantiation.
  instantiation,

  /// A simulation-only process, such as a timed clock source.
  simulationProcess,
}

/// Context supplied when resolving a [BackendArtifact].
class BackendArtifactContext {
  /// Requested backend.
  final EmissionBackend backend;

  /// Requested artifact location.
  final BackendArtifactKind kind;

  /// Definition type for a definition artifact.
  final String? definitionType;

  /// Instance type for an instantiation artifact.
  final String? instanceType;

  /// Instance name for an instantiation artifact.
  final String? instanceName;

  /// Resolved port expressions for an instantiation artifact.
  final Map<String, String> ports;

  /// Creates a backend artifact context.
  const BackendArtifactContext({
    required this.backend,
    required this.kind,
    this.definitionType,
    this.instanceType,
    this.instanceName,
    this.ports = const {},
  });

  /// Creates a definition artifact context.
  const BackendArtifactContext.definition({
    required EmissionBackend backend,
    required String definitionType,
  }) : this(
          backend: backend,
          kind: BackendArtifactKind.definition,
          definitionType: definitionType,
        );

  /// Creates an instantiation artifact context.
  const BackendArtifactContext.instantiation({
    required EmissionBackend backend,
    required String instanceType,
    required String instanceName,
    required Map<String, String> ports,
  }) : this(
          backend: backend,
          kind: BackendArtifactKind.instantiation,
          instanceType: instanceType,
          instanceName: instanceName,
          ports: ports,
        );
}

/// Backend-specific source emitted for one [BackendArtifactContext].
class BackendArtifact {
  /// The backend this artifact targets.
  final EmissionBackend backend;

  /// The location where this artifact is emitted.
  final BackendArtifactKind kind;

  /// Complete backend source for this artifact.
  final String contents;

  /// Creates a backend-specific source artifact.
  const BackendArtifact({
    required this.backend,
    required this.kind,
    required this.contents,
  });
}

/// Optional mixin for modules with backend-specific emission artifacts.
mixin BackendArtifactProvider {
  /// Returns a backend-specific artifact for [context], if one is available.
  BackendArtifact? artifactFor(BackendArtifactContext context) => null;
}
