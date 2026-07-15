// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// cross_probe_service.dart
// Interfaces and local implementations for cross-probing between viewers.
//
// 2026 June
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/foundation.dart';

/// Abstract interface for cross-probing signal selections between viewers.
///
/// Cross-probing allows a user to select signals in one viewer (e.g. the
/// schematic) and have those signals automatically highlighted in all other
/// viewers (e.g. the waveform viewer).
abstract class CrossProbeService {
  /// Whether cross-probing is currently active.
  ///
  /// When `false`, neither [send] broadcasts nor incoming messages from
  /// the channel are delivered to [incomingSignals].
  ValueNotifier<bool> get isActive;

  /// The most recent incoming signal paths received from OTHER viewers.
  ///
  /// Updated whenever another viewer broadcasts a selection while
  /// [isActive] is `true`.  `null` until the first message arrives.
  ValueNotifier<List<String>?> get incomingSignals;

  /// Broadcast [signalPaths] from this viewer ([source]) to all others.
  ///
  /// [source] identifies the originating viewer (e.g. `'waveform'`,
  /// `'schematic'`).  [LocalCrossProbeService] uses this tag to filter
  /// out its own broadcasts so it does not receive its own selections as
  /// incoming signals.
  ///
  /// Does nothing when [isActive] is `false` or [signalPaths] is empty.
  void send(List<String> signalPaths, {required String source});

  /// Release all resources held by this service.
  void dispose();
}

// ─────────────────────────────────────────────────────────────────────────────
// Local (in-process) implementation
// ─────────────────────────────────────────────────────────────────────────────

/// Shared in-process broadcast channel.
///
/// Create a single [LocalCrossProbeChannel] and share it among all
/// [LocalCrossProbeService] instances that should cross-probe with each other.
/// This replaces the older `SignalSelectionBus` pattern.
class LocalCrossProbeChannel extends ChangeNotifier {
  String? _lastSource;
  List<String>? _lastPaths;

  /// The source tag of the most recent broadcast.
  String? get lastSource => _lastSource;

  /// The signal paths of the most recent broadcast.
  List<String>? get lastPaths => _lastPaths;

  /// Broadcast [signalPaths] from [source] to all registered listeners.
  ///
  /// Does nothing when [signalPaths] is empty.
  void broadcast(List<String> signalPaths, String source) {
    if (signalPaths.isEmpty) return;
    _lastSource = source;
    _lastPaths = List.unmodifiable(signalPaths);
    notifyListeners();
  }
}

/// Per-viewer [CrossProbeService] backed by a shared [LocalCrossProbeChannel].
///
/// Create one [LocalCrossProbeService] per viewer, all sharing the same
/// [LocalCrossProbeChannel].  Each service filters out its own broadcasts
/// (matched by [source]) so viewers do not receive their own selections.
///
/// ```dart
/// final channel  = LocalCrossProbeChannel();
/// final waveXp   = LocalCrossProbeService(channel, source: 'waveform');
/// final schemXp  = LocalCrossProbeService(channel, source: 'schematic');
///
/// // Pass waveXp to the wave viewer and schemXp to the schematic viewer.
/// // dispose both services and the channel when done.
/// ```
class LocalCrossProbeService implements CrossProbeService {
  final LocalCrossProbeChannel _channel;
  final String _source;

  @override
  final ValueNotifier<bool> isActive = ValueNotifier<bool>(true);

  @override
  final ValueNotifier<List<String>?> incomingSignals =
      ValueNotifier<List<String>?>(null);

  /// Creates a [LocalCrossProbeService] backed by [channel].
  ///
  /// [source] is the identifier used to filter self-broadcasts.  Use a
  /// stable, descriptive tag such as `'waveform'` or `'schematic'`.
  LocalCrossProbeService(
    LocalCrossProbeChannel channel, {
    required String source,
  })  : _channel = channel,
        _source = source {
    _channel.addListener(_onChannelMessage);
  }

  void _onChannelMessage() {
    if (!isActive.value) return;
    final src = _channel.lastSource;
    if (src == null || src == _source) return; // ignore own broadcasts
    incomingSignals.value = _channel.lastPaths;
  }

  @override
  void send(List<String> signalPaths, {required String source}) {
    if (!isActive.value || signalPaths.isEmpty) return;
    _channel.broadcast(signalPaths, source);
  }

  @override
  void dispose() {
    _channel.removeListener(_onChannelMessage);
    isActive.dispose();
    incomingSignals.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Null (no-op) implementation
// ─────────────────────────────────────────────────────────────────────────────

/// A no-op [CrossProbeService] for standalone or offline contexts where
/// cross-probing between viewers is not available.
///
/// [isActive] is always `false`; [send] is a no-op; [incomingSignals]
/// never changes.
class NullCrossProbeService implements CrossProbeService {
  @override
  final ValueNotifier<bool> isActive = ValueNotifier<bool>(false);

  @override
  final ValueNotifier<List<String>?> incomingSignals =
      ValueNotifier<List<String>?>(null);

  @override
  void send(List<String> signalPaths, {required String source}) {}

  @override
  void dispose() {
    isActive.dispose();
    incomingSignals.dispose();
  }
}
