// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_extension_status.dart
// Shared data model for the ROHD extension handshake protocol.
//
// Used by both rohd-schematic-viewer and rohd-wave-viewer to represent
// what source formats and files the ROHD extension has available for a
// given module.
//
// 2026 May
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

/// Identifies a source/output format the ROHD extension can navigate to.
enum RohdSourceFormat {
  /// ROHD Dart source (the design description language).
  rohd,

  /// SystemVerilog output generated from ROHD.
  sv,

  /// SystemC output generated from ROHD.
  sc,

  /// FST/VCD waveform file associated with a simulation of this module.
  fst,
}

/// Availability status for a single source format.
class RohdFormatInfo {
  /// At least one source frame exists for this format in the FLC data.
  final bool available;

  /// The source file was found on disk (checked by the extension host).
  /// May be `false` even when [available] is `true` if the file was
  /// deleted or the path is stale.
  final bool fileFound;

  /// Resolved absolute path to the file, if known.
  final String? path;

  const RohdFormatInfo({
    required this.available,
    this.fileFound = false,
    this.path,
  });

  /// A format is usable when the FLC data says it exists AND the file was
  /// found.  Callers may also choose to show the option when [available] is
  /// true but [fileFound] is false (degraded / missing-file indication).
  bool get usable => available && fileFound;
}

/// Information returned by the ROHD extension for a specific module.
///
/// Viewers use this to decide which "Go to …" menu items to display and
/// whether to show a status icon indicating that the extension is connected.
class RohdModuleInfo {
  /// Whether the ROHD extension responded to the query.
  ///
  /// `false` means the extension is not installed, not running, or the
  /// viewer is operating in a context where the extension is not reachable
  /// (e.g. fully standalone mode).
  final bool extensionAvailable;

  /// The module definition name that was queried (e.g. `'Counter_L1_'`).
  final String? module;

  /// Per-format availability, keyed by [RohdSourceFormat].
  ///
  /// Only formats mentioned here have been checked; absent entries mean
  /// "unknown / not checked".
  final Map<RohdSourceFormat, RohdFormatInfo> formats;

  /// A human-readable error message if the query failed, null otherwise.
  final String? error;

  /// Whether the DTD `rohd` service appears healthy for source navigation.
  ///
  /// `null` means the client did not perform a DTD health check. `false`
  /// means the service is missing, incomplete, or registered by an owner that
  /// does not advertise the expected ROHD bridge capabilities.
  final bool? dtdHealthy;

  /// True when the DTD `rohd` service is registered but does not advertise
  /// the expected ROHD bridge capability marker.
  final bool dtdRegistrationConflict;

  /// Human-readable DTD health detail for UI display.
  final String? dtdStatusMessage;

  /// `true` while the extension is still loading an FST file asynchronously.
  final bool fstLoading;

  const RohdModuleInfo({
    required this.extensionAvailable,
    this.module,
    this.formats = const {},
    this.error,
    this.dtdHealthy,
    this.dtdRegistrationConflict = false,
    this.dtdStatusMessage,
    this.fstLoading = false,
  });

  /// Sentinel value used when the extension is not available.
  static const RohdModuleInfo unavailable = RohdModuleInfo(
    extensionAvailable: false,
  );

  // ── Convenience accessors ─────────────────────────────────────────────────

  /// Whether the module has ROHD Dart source available and found on disk.
  bool get hasRohd => formats[RohdSourceFormat.rohd]?.usable ?? false;

  /// Whether the module has SystemVerilog output available and found on disk.
  bool get hasSv => formats[RohdSourceFormat.sv]?.usable ?? false;

  /// Whether the module has SystemC output available and found on disk.
  bool get hasSc => formats[RohdSourceFormat.sc]?.usable ?? false;

  /// Whether a waveform file (FST/VCD) is available and found on disk.
  bool get hasFst => formats[RohdSourceFormat.fst]?.usable ?? false;

  /// All format names for which data is available (as lower-case strings).
  List<String> get availableFormatNames => [
        if (hasRohd) 'rohd',
        if (hasSv) 'sv',
        if (hasSc) 'sc',
        if (hasFst) 'fst',
      ];

  /// True when any source navigation format is available.
  bool get hasAnySource => hasRohd || hasSv || hasSc;

  /// All source-navigable formats (ROHD, SV, SystemC) that are usable for
  /// this module, in display order.  Excludes [RohdSourceFormat.fst] (a
  /// waveform, not a navigable source).
  List<RohdSourceFormat> get navigableSourceFormats => [
        if (hasRohd) RohdSourceFormat.rohd,
        if (hasSv) RohdSourceFormat.sv,
        if (hasSc) RohdSourceFormat.sc,
      ];

  /// Human-readable label for a format.
  static String formatLabel(RohdSourceFormat fmt) => switch (fmt) {
        RohdSourceFormat.rohd => 'ROHD (Dart)',
        RohdSourceFormat.sv => 'SystemVerilog',
        RohdSourceFormat.sc => 'SystemC',
        RohdSourceFormat.fst => 'Waveform (FST)',
      };

  /// Build from a JSON map (as returned by the extension host or DTD).
  factory RohdModuleInfo.fromJson(Map<String, dynamic> json) {
    final available = json['extensionAvailable'] as bool? ?? false;
    final module = json['module'] as String?;
    final error = json['error'] as String?;
    final dtdHealthy = json['dtdHealthy'] as bool?;
    final dtdRegistrationConflict =
        json['dtdRegistrationConflict'] as bool? ?? false;
    final dtdStatusMessage = json['dtdStatusMessage'] as String?;
    final fstLoading = json['fstLoading'] as bool? ?? false;

    final rawFormats = json['formats'] as Map<String, dynamic>? ?? const {};
    final formats = <RohdSourceFormat, RohdFormatInfo>{};
    for (final entry in rawFormats.entries) {
      final fmt = _parseFormat(entry.key);
      if (fmt == null) continue;
      final fmtMap = entry.value as Map<String, dynamic>? ?? const {};
      formats[fmt] = RohdFormatInfo(
        available: fmtMap['available'] as bool? ?? false,
        fileFound: fmtMap['fileFound'] as bool? ?? false,
        path: fmtMap['path'] as String?,
      );
    }

    return RohdModuleInfo(
      extensionAvailable: available,
      module: module,
      formats: formats,
      error: error,
      dtdHealthy: dtdHealthy,
      dtdRegistrationConflict: dtdRegistrationConflict,
      dtdStatusMessage: dtdStatusMessage,
      fstLoading: fstLoading,
    );
  }

  /// Serialize to JSON for transmission over DTD or postMessage.
  Map<String, dynamic> toJson() => {
        'extensionAvailable': extensionAvailable,
        if (module != null) 'module': module,
        'formats': {
          for (final e in formats.entries)
            _formatKey(e.key): {
              'available': e.value.available,
              'fileFound': e.value.fileFound,
              if (e.value.path != null) 'path': e.value.path,
            },
        },
        if (error != null) 'error': error,
        if (dtdHealthy != null) 'dtdHealthy': dtdHealthy,
        if (dtdRegistrationConflict)
          'dtdRegistrationConflict': dtdRegistrationConflict,
        if (dtdStatusMessage != null) 'dtdStatusMessage': dtdStatusMessage,
        'fstLoading': fstLoading,
      };

  static RohdSourceFormat? _parseFormat(String key) => switch (key) {
        'rohd' => RohdSourceFormat.rohd,
        'sv' => RohdSourceFormat.sv,
        'sc' => RohdSourceFormat.sc,
        'fst' => RohdSourceFormat.fst,
        _ => null,
      };

  static String _formatKey(RohdSourceFormat fmt) => switch (fmt) {
        RohdSourceFormat.rohd => 'rohd',
        RohdSourceFormat.sv => 'sv',
        RohdSourceFormat.sc => 'sc',
        RohdSourceFormat.fst => 'fst',
      };
}
