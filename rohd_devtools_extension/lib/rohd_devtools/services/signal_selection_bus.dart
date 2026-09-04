// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_selection_bus.dart
// Cross-widget signal selection bus for cross-probing between
// schematic viewer, waveform viewer, and other panels.

import 'package:flutter/widgets.dart';

/// A signal sent on the [SignalSelectionBus].
///
/// Each signal path is a hierarchy path like `"module/sub/signal_name"`.
class SignalSelectionMessage {
  /// The hierarchy paths of the selected signals.
  final List<String> signalPaths;

  /// Which widget originated this message (so receivers can ignore their own).
  final String source;

  /// Creates a [SignalSelectionMessage].
  const SignalSelectionMessage({
    required this.signalPaths,
    required this.source,
  });

  @override
  String toString() =>
      'SignalSelectionMessage(source: $source, paths: $signalPaths)';
}

/// A shared bus that widgets use to send and receive signal selections
/// for cross-probing.
///
/// Usage:
/// - Call [send] to broadcast a set of signal paths.
/// - Listen via [addListener] (inherited from [ChangeNotifier]).
/// - Read [lastMessage] to get the most recent broadcast.
class SignalSelectionBus extends ChangeNotifier {
  SignalSelectionMessage? _lastMessage;

  /// The most recently sent message, or `null` if nothing has been sent.
  SignalSelectionMessage? get lastMessage => _lastMessage;

  /// Broadcast [signalPaths] from [source] to all listeners.
  void send({required List<String> signalPaths, required String source}) {
    if (signalPaths.isEmpty) {
      return;
    }
    _lastMessage = SignalSelectionMessage(
      signalPaths: signalPaths,
      source: source,
    );
    notifyListeners();
  }
}

/// Provides a [SignalSelectionBus] to the widget tree.
class SignalSelectionBusProvider extends InheritedWidget {
  /// The shared bus instance.
  final SignalSelectionBus _bus;

  /// Creates a [SignalSelectionBusProvider].
  const SignalSelectionBusProvider({
    required SignalSelectionBus bus,
    required super.child,
    super.key,
  }) : _bus = bus;

  /// Retrieve the bus from the nearest ancestor, or `null` if none.
  static SignalSelectionBus? of(BuildContext context) {
    final provider = context
        .dependOnInheritedWidgetOfExactType<SignalSelectionBusProvider>();
    return provider?._bus;
  }

  @override
  bool updateShouldNotify(SignalSelectionBusProvider oldWidget) =>
      _bus != oldWidget._bus;
}
