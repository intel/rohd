// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// vm_connection_form.dart
// Reusable VM connection form widget for both initial screen and dialog.
//
// 2026 February
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/platform_icon.dart';

/// Describes a single VM service discovered via DTD.
class DiscoveredVmService with Diagnosticable {
  /// Human-readable name (may be null).
  final String? name;

  /// Direct VM service URI.
  final String uri;

  /// Exposed/forwarded URI (preferred over [uri] when available).
  final String? exposedUri;

  /// Whether this VM service is currently reachable.
  ///
  /// Set to `false` by auto-rediscovery when the service is no longer
  /// found via the DTD.  Dead services are shown grayed-out in the list.
  bool isAlive;

  /// Whether to automatically reconnect to this VM by name if it dies
  /// and a new VM with the same name appears via DTD discovery.
  bool autoReconnect;

  /// The URI to use for connection (prefers exposedUri).
  String get connectionUri => exposedUri ?? uri;

  /// Construction for [DiscoveredVmService].
  DiscoveredVmService({
    required this.uri,
    this.name,
    this.exposedUri,
    this.isAlive = true,
    this.autoReconnect = false,
  });

  /// A compact display label.
  String get displayLabel {
    final label = name ?? 'VM Service';
    final preview = connectionUri.length > 50
        ? '${connectionUri.substring(0, 50)}…'
        : connectionUri;
    return '$label — '
        '$preview';
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(StringProperty('name', name))
      ..add(StringProperty('uri', uri))
      ..add(StringProperty('exposedUri', exposedUri))
      ..add(FlagProperty('isAlive', value: isAlive))
      ..add(FlagProperty('autoReconnect', value: autoReconnect))
      ..add(StringProperty('connectionUri', connectionUri))
      ..add(StringProperty('displayLabel', displayLabel));
  }
}

/// Callback that discovers VM services from a DTD URI.
///
/// Returns the list of services found, or throws on error.
typedef DiscoverVmServicesCallback = Future<List<DiscoveredVmService>> Function(
    String dtdUri);

/// Reusable VM connection form that can be embedded in different contexts.
///
/// This widget encapsulates the DTD URI discovery and VM Service URI input,
/// and can be used both as the initial connection screen and in dialogs.
///
/// Layout (top to bottom):
/// 1. DTD URI field + Discover button
/// 2. Discovered VM list (when available)
/// 3. VM Service URI field (manual override)
/// 4. Connect button
class VmConnectionForm extends StatefulWidget {
  /// Controller for VM Service URI
  final TextEditingController vmServiceUriController;

  /// Controller for DTD URI
  final TextEditingController dtdUriController;

  /// Current connection error message (if any)
  final String? connectionError;

  /// Callback when Connect button is pressed
  final VoidCallback onConnect;

  /// Callback when Demo mode button is pressed (optional)
  final VoidCallback? onDemoMode;

  /// Whether to show the demo mode button and help text
  final bool showDemoButton;

  /// Whether emoji colors are available (for platform icons)
  final bool hasColorEmoji;

  /// Callback to clean VM Service URIs
  final String Function(String) cleanVmServiceUri;

  /// Callback to clean DTD URIs
  final String Function(String) cleanDtdUri;

  /// Callback that discovers VM services from a DTD URI.
  final DiscoverVmServicesCallback? discoverVmServices;

  /// Previously discovered services to pre-populate the list.
  ///
  /// When returning to the connection screen after a VM death, the parent
  /// passes the remembered list (with [DiscoveredVmService.isAlive] set
  /// appropriately) so the user can see which VMs are still available.
  final List<DiscoveredVmService>? initialDiscoveredServices;

  /// Called whenever the form discovers (or re-discovers) VM services.
  ///
  /// The parent should save this list so it can be passed back as
  /// [initialDiscoveredServices] if the connection screen is shown again.
  final ValueChanged<List<DiscoveredVmService>>? onServicesDiscovered;

  /// Construction for [VmConnectionForm].
  const VmConnectionForm({
    required this.vmServiceUriController,
    required this.dtdUriController,
    required this.onConnect,
    required this.cleanVmServiceUri,
    required this.cleanDtdUri,
    this.connectionError,
    this.onDemoMode,
    this.showDemoButton = false,
    this.hasColorEmoji = false,
    this.discoverVmServices,
    this.initialDiscoveredServices,
    this.onServicesDiscovered,
    super.key,
  });

  @override

  /// Creates the state object for the VM connection form.
  State<VmConnectionForm> createState() => _VmConnectionFormState();

  @override

  /// Adds diagnostic properties for the connection form.
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(
        DiagnosticsProperty<TextEditingController>(
          'vmServiceUriController',
          vmServiceUriController,
        ),
      )
      ..add(
        DiagnosticsProperty<TextEditingController>(
          'dtdUriController',
          dtdUriController,
        ),
      )
      ..add(StringProperty('connectionError', connectionError))
      ..add(
        ObjectFlagProperty<VoidCallback>(
          'onConnect',
          onConnect,
          ifNull: 'disabled',
        ),
      )
      ..add(
        ObjectFlagProperty<VoidCallback?>(
          'onDemoMode',
          onDemoMode,
          ifNull: 'disabled',
        ),
      )
      ..add(FlagProperty('showDemoButton', value: showDemoButton))
      ..add(FlagProperty('hasColorEmoji', value: hasColorEmoji))
      ..add(
        DiagnosticsProperty<String Function(String)>(
          'cleanVmServiceUri',
          cleanVmServiceUri,
        ),
      )
      ..add(
        DiagnosticsProperty<String Function(String)>(
          'cleanDtdUri',
          cleanDtdUri,
        ),
      )
      ..add(
        ObjectFlagProperty<DiscoverVmServicesCallback?>(
          'discoverVmServices',
          discoverVmServices,
          ifNull: 'disabled',
        ),
      )
      ..add(
        DiagnosticsProperty<List<DiscoveredVmService>?>(
          'initialDiscoveredServices',
          initialDiscoveredServices,
        ),
      )
      ..add(
        ObjectFlagProperty<ValueChanged<List<DiscoveredVmService>>?>(
          'onServicesDiscovered',
          onServicesDiscovered,
          ifNull: 'disabled',
        ),
      );
  }
}

class _VmConnectionFormState extends State<VmConnectionForm> {
  List<DiscoveredVmService>? _discoveredServices;
  bool _isDiscovering = false;
  bool _discoveryCancelled = false;
  String? _discoveryError;

  void _connect() {
    final raw = widget.vmServiceUriController.text;
    final cleaned = widget.cleanVmServiceUri(raw);
    if (cleaned.isNotEmpty && cleaned != raw) {
      widget.vmServiceUriController.text = cleaned;
      widget.vmServiceUriController.selection =
          TextSelection.collapsed(offset: cleaned.length);
    }
    widget.onConnect();
  }

  @override
  void initState() {
    super.initState();
    // Pre-populate with remembered services (may include dead ones)
    if (widget.initialDiscoveredServices != null) {
      _discoveredServices = List<DiscoveredVmService>.from(
        widget.initialDiscoveredServices!,
      );
    } else if (widget.dtdUriController.text.isNotEmpty &&
        widget.discoverVmServices != null) {
      // DTD URI is already set (e.g. app reload) — auto-discover.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_discoverServices());
        }
      });
    }
  }

  Future<void> _discoverServices() async {
    final raw = widget.dtdUriController.text;
    if (raw.isEmpty) {
      return;
    }

    final cleaned = widget.cleanDtdUri(raw);
    if (!cleaned.startsWith('ws')) {
      return;
    }

    widget.dtdUriController.text = cleaned;

    if (widget.discoverVmServices == null) {
      return;
    }

    setState(() {
      _isDiscovering = true;
      _discoveryCancelled = false;
      _discoveryError = null;
      _discoveredServices = null;
    });

    try {
      final services = await widget.discoverVmServices!(cleaned);
      if (!mounted || _discoveryCancelled) {
        return;
      }
      setState(() {
        _isDiscovering = false;
        _discoveredServices = services;
        if (services.isEmpty) {
          _discoveryError = 'No VM services found. Is your app running?';
        } else if (services.length == 1) {
          // Auto-select the only service and enable auto-reconnect
          widget.vmServiceUriController.text = services.first.connectionUri;
          services.first.autoReconnect = true;
        }
      });
      // Notify parent so it can remember these across reconnects
      widget.onServicesDiscovered?.call(services);
    } on Exception catch (e) {
      if (!mounted) {
        return;
      }

      // Determine the specific error to display better messages
      final errorStr = e.toString().toLowerCase();
      final errorMessage = _getDiscoveryErrorMessage(errorStr, cleaned);

      setState(() {
        _isDiscovering = false;
        _discoveryError = errorMessage;
      });
    }
  }

  /// Generates a user-friendly error message based on the exception type.
  ///
  /// Distinguishes between DTD connection errors (invalid address)
  /// and other errors, providing specific guidance for each case.
  String _getDiscoveryErrorMessage(String errorStr, String dtdUri) {
    // Check for WebSocket connection errors (invalid DTD address)
    if (errorStr.contains('websocket') ||
        errorStr.contains('connection') ||
        errorStr.contains('failed to connect') ||
        errorStr.contains('refused')) {
      return 'Failed to connect to DTD address: $dtdUri. '
          'Please verify the URI is correct and the Dart Tooling Daemon '
          'is running.';
    }

    // Check for socket timeouts or DNS resolution errors
    if (errorStr.contains('timeout') || errorStr.contains('dns')) {
      return 'Connection to DTD timed out or could not resolve '
          'address: $dtdUri. '
          'Please verify the DTD address is reachable.';
    }

    // Check for certificate/SSL errors
    if (errorStr.contains('certificate') || errorStr.contains('ssl')) {
      return 'SSL/certificate error connecting to DTD. '
          'Make sure the DTD certificate is valid.';
    }

    // For other errors, provide a generic message
    return 'Discovery failed. Please verify the DTD URI is correct '
        'and check the console for more details.';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Title (only on full-screen layout)
          if (widget.showDemoButton) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                platformIcon(
                  Icons.developer_board,
                  '🔧',
                  size: 32,
                  hasColorEmoji: widget.hasColorEmoji,
                ),
                const SizedBox(width: 12),
                Text(
                  'Connect to Dart VM',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],

          // ── 1. DTD URI field ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: widget.dtdUriController,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  enableSuggestions: false,
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  decoration: InputDecoration(
                    labelText: 'DTD URI (auto-discover VMs)',
                    hintText: 'ws://127.0.0.1:xxxxx/xxxxx=',
                    border: const OutlineInputBorder(),
                    prefixIcon: platformIcon(
                      Icons.cloud,
                      '☁️',
                      size: 20,
                      hasColorEmoji: widget.hasColorEmoji,
                    ),
                  ),
                  onSubmitted: (_) => _discoverServices(),
                ),
              ),
              const SizedBox(width: 8),
              if (_isDiscovering) ...[
                const SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: null,
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 56,
                  child: TextButton(
                    onPressed: () {
                      setState(() {
                        _discoveryCancelled = true;
                        _isDiscovering = false;
                      });
                    },
                    child: const Text('Cancel'),
                  ),
                ),
              ] else
                SizedBox(
                  height: 56, // match TextField height
                  child: ElevatedButton(
                    onPressed: _discoverServices,
                    child: const Text('Discover'),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // ── 2. Discovered VM list ──
          if (_discoveredServices != null &&
              _discoveredServices!.isNotEmpty) ...[
            Builder(
              builder: (context) {
                final aliveCount =
                    _discoveredServices!.where((s) => s.isAlive).length;
                final deadCount = _discoveredServices!.length - aliveCount;
                final label = deadCount > 0
                    ? '$aliveCount VM service(s) available ($deadCount ended):'
                    : '${_discoveredServices!.length} VM service(s) found:';
                return Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                );
              },
            ),
            const SizedBox(height: 4),
            Container(
              constraints: const BoxConstraints(maxHeight: 160),
              decoration: BoxDecoration(
                border: Border.all(
                  color: isDark ? Colors.white24 : Colors.black12,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _discoveredServices!.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final svc = _discoveredServices![index];
                  final isDead = !svc.isAlive;
                  final isSelected = !isDead &&
                      widget.vmServiceUriController.text == svc.connectionUri;
                  return ListTile(
                    dense: true,
                    selected: isSelected,
                    selectedTileColor: isDark
                        ? Colors.blue.shade900.withValues(alpha: 0.4)
                        : Colors.blue.shade50,
                    leading: platformIcon(
                      isDead ? Icons.cloud_off : Icons.memory,
                      isDead ? '🔌' : '🔌',
                      size: 18,
                      hasColorEmoji: widget.hasColorEmoji,
                      color: isDead ? Colors.grey : null,
                    ),
                    title: Text(
                      svc.name ?? 'VM Service ${index + 1}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isDead ? Colors.grey : null,
                      ),
                    ),
                    subtitle: Text(
                      isDead
                          ? '${svc.connectionUri} (ended)'
                          : svc.connectionUri,
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: isDead ? Colors.grey : null,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: isDead
                        ? null
                        : Tooltip(
                            message: 'Automatic Reconnect',
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: Checkbox(
                                value: svc.autoReconnect,
                                onChanged: (value) {
                                  setState(() {
                                    svc.autoReconnect = value ?? false;
                                  });
                                  widget.onServicesDiscovered?.call(
                                    _discoveredServices!,
                                  );
                                },
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ),
                    onTap: () {
                      setState(() {
                        widget.vmServiceUriController.text = svc.connectionUri;
                      });
                      // Alive VMs connect immediately; dead VMs just fill
                      // the URI field so the user can edit before connecting.
                      if (!isDead) {
                        widget.onConnect();
                      }
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Discovery error
          if (_discoveryError != null) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _discoveryError!,
                style: const TextStyle(color: Colors.orange, fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ── 3. VM Service URI field (manual / override) ──
          TextField(
            controller: widget.vmServiceUriController,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            smartDashesType: SmartDashesType.disabled,
            smartQuotesType: SmartQuotesType.disabled,
            decoration: InputDecoration(
              labelText: 'VM Service URI',
              hintText: 'ws://127.0.0.1:8181/xxxx=/ws',
              border: const OutlineInputBorder(),
              prefixIcon: platformIcon(
                Icons.link,
                '🔗',
                size: 20,
                hasColorEmoji: widget.hasColorEmoji,
              ),
            ),
            onSubmitted: (_) => _connect(),
          ),
          const SizedBox(height: 16),

          // Connection error
          if (widget.connectionError != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  platformIcon(
                    Icons.error,
                    '❌',
                    color: Colors.red,
                    size: 20,
                    hasColorEmoji: widget.hasColorEmoji,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.connectionError!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
          if (widget.connectionError != null) const SizedBox(height: 16),

          // ── 4. Connect button ──
          ElevatedButton.icon(
            onPressed: _connect,
            icon: platformIcon(
              Icons.power,
              '⚡',
              size: 20,
              hasColorEmoji: widget.hasColorEmoji,
            ),
            label: const Text('Connect'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),

          // Full-screen layout: demo mode button and help text
          if (widget.showDemoButton && widget.onDemoMode != null) ...[
            const SizedBox(height: 16),

            // Divider
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'OR',
                    style: TextStyle(
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 16),

            // Demo mode button
            OutlinedButton.icon(
              onPressed: widget.onDemoMode,
              icon: platformIcon(
                Icons.play_arrow,
                '▶️',
                size: 20,
                hasColorEmoji: widget.hasColorEmoji,
              ),
              label: const Text('Continue without Connection (Demo examples)'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 24),

            // Help text
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'To connect to a running ROHD app:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '1. Run your app with: dart run -- '
                    'observe your_app.dart\n'
                    '2. Copy the VM service URI from the console\n'
                    '3. Paste it above and click Connect',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
