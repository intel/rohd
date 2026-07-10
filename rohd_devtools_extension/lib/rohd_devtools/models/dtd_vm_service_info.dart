// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// dtd_vm_service_info.dart
// Thin wrapper around the SDK's VmServiceInfo that adds UI state
// (autoReconnect, isAlive) for use in the connection form and
// auto-reconnect logic.
//
// 2026 June
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:dtd/dtd.dart';

/// Information about a discovered VM service, wrapping the SDK's
/// VmServiceInfo with additional UI-specific mutable state.
///
/// Used by the VM connection form to display the list of available VMs
/// and by the auto-reconnect logic to match VMs by name.
class DtdVmServiceInfo {
  /// The underlying SDK VM service info.
  final VmServiceInfo info;

  /// Whether this VM service is currently reachable.
  ///
  /// Set to `false` by auto-rediscovery when the service is no longer
  /// found via the DTD.  Dead services are shown grayed-out in the list.
  bool isAlive;

  /// Whether to automatically reconnect to this VM by name if it dies
  /// and a new VM with the same name appears via DTD discovery.
  bool autoReconnect;

  /// Creates a [DtdVmServiceInfo] wrapping the given [info].
  DtdVmServiceInfo({
    required this.info,
    this.isAlive = true,
    this.autoReconnect = false,
  });

  /// Creates a [DtdVmServiceInfo] from individual fields (convenience).
  factory DtdVmServiceInfo.fromFields({
    required String uri,
    String? name,
    String? exposedUri,
    bool isAlive = true,
    bool autoReconnect = false,
  }) =>
      DtdVmServiceInfo(
        info: VmServiceInfo(uri: uri, exposedUri: exposedUri, name: name),
        isAlive: isAlive,
        autoReconnect: autoReconnect,
      );

  /// Human-readable name (may be null).
  String? get name => info.name;

  /// Direct VM service URI.
  String get uri => info.uri;

  /// Exposed/forwarded URI (preferred over [uri] when available).
  String? get exposedUri => info.exposedUri;

  /// The URI to use for connection (prefers exposedUri).
  String get connectionUri => exposedUri ?? uri;

  /// A compact display label.
  String get displayLabel {
    final label = name ?? 'VM Service';
    final uriLabel = connectionUri.length > 50
        ? '${connectionUri.substring(0, 50)}…'
        : connectionUri;
    return '$label — $uriLabel';
  }
}
