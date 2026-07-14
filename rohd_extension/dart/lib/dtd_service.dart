// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// dtd_service.dart
// DTD service handler for receiving cross-probe source navigation
// requests from the ROHD DevTools extension.
//
// Registers a `rohd.goToSource` service on the Dart Tooling Daemon so
// that the DevTools extension can send resolved SourceFrame lists for
// navigation in the VS Code editor.
//
// 2026 April 27
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async';
import 'dart:convert';

import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'source_navigator.dart';

/// Callback invoked when the DTD service receives a goToSource request.
///
/// The TS shell provides this callback to bridge DTD requests into
/// VS Code command execution.
typedef GoToSourceCallback = Future<void> Function(List<SourceFrame> frames,
    {int startIndex});

/// Manages the DTD connection and service registration for source
/// navigation.
class DtdService {
  final GoToSourceCallback _onGoToSource;
  Peer? _peer;
  WebSocketChannel? _channel;
  bool _disposed = false;

  /// Creates a DTD service that calls [onGoToSource] when a
  /// `rohd.goToSource` request arrives.
  DtdService({required GoToSourceCallback onGoToSource})
      : _onGoToSource = onGoToSource;

  /// Connect to the DTD at [uri] and register the `rohd.goToSource`
  /// service.
  ///
  /// Returns `true` if connection and registration succeeded.
  Future<bool> connect(String uri) async {
    if (_disposed) return false;

    try {
      _channel = WebSocketChannel.connect(Uri.parse(uri));
      await _channel!.ready;
      _peer = Peer(_channel!.cast<String>());

      // Register the service method.
      _peer!.registerMethod('rohd.goToSource', _handleGoToSource);

      // Start listening (non-blocking).
      unawaited(
        _peer!.listen().then((_) {
          // Connection closed.
          _peer = null;
        }),
      );

      return true;
    } on Exception catch (e) {
      _peer = null;
      _channel = null;
      // ignore: avoid_print
      print('[DtdService] Failed to connect to DTD at $uri: $e');
      return false;
    }
  }

  /// Whether the DTD connection is active.
  bool get isConnected => _peer != null && !_peer!.isClosed;

  /// Disconnect from DTD and clean up.
  Future<void> dispose() async {
    _disposed = true;
    await _peer?.close();
    _peer = null;
    await _channel?.sink.close();
    _channel = null;
  }

  // ---------------------------------------------------------------------------
  // RPC handler
  // ---------------------------------------------------------------------------

  /// Handle an incoming `rohd.goToSource` request.
  ///
  /// Expected parameters:
  /// ```json
  /// {
  ///   "frames": [
  ///     {"file": "lib/src/foo.dart", "line": 42, "col": 5, "type": "rohd"},
  ///     {"file": "Foo.sv", "line": 10, "col": 1, "type": "sv"}
  ///   ],
  ///   "index": 0   // optional starting frame
  /// }
  /// ```
  Future<Map<String, dynamic>> _handleGoToSource(Parameters params) async {
    try {
      final framesRaw = params['frames'].asList;
      final startIndex = params['index'].asIntOr(0);

      final frames = framesRaw.map((raw) {
        final map = raw as Map<String, dynamic>;
        return SourceFrame.fromJson(map);
      }).toList();

      if (frames.isEmpty) {
        return {'status': 'error', 'message': 'No frames provided'};
      }

      await _onGoToSource(frames, startIndex: startIndex);
      return {'status': 'ok', 'navigated': frames.length};
    } on Exception catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }
}

// ---------------------------------------------------------------------------
// Convenience: encode/decode frames for stdio-based communication
// ---------------------------------------------------------------------------

/// Encode a goToSource request as a JSON string for stdio transport.
String encodeGoToSourceRequest(List<SourceFrame> frames, {int index = 0}) =>
    jsonEncode({
      'method': 'rohd.goToSource',
      'frames': frames.map((f) => f.toJson()).toList(),
      'index': index,
    });

/// Decode a goToSource request from a JSON string.
(List<SourceFrame>, int) decodeGoToSourceRequest(String json) {
  final map = jsonDecode(json) as Map<String, dynamic>;
  final framesRaw = map['frames'] as List<dynamic>;
  final index = (map['index'] as int?) ?? 0;
  final frames = framesRaw
      .map((raw) => SourceFrame.fromJson(raw as Map<String, dynamic>))
      .toList();
  return (frames, index);
}
