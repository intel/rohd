// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:convert';

import 'package:rohd_devtools_extension/rohd_devtools/models/tree_model.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/tree_data_source.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/waveform_data_source.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_schematic_viewer/schematic_connectivity.dart';

/// Read-only hierarchy traversal facade shared by terminal and AI clients.
///
/// [OccurrenceAddress] is the stable wire identity for hierarchy and waveform
/// queries. Paths are returned as human-readable aliases, never as identity.
class DesignTraversalCli {
  /// Creates a hierarchy traversal facade rooted at [root].
  DesignTraversalCli(HierarchyOccurrence root)
      : _hierarchy = BaseHierarchyAdapter.fromTree(root);

  final HierarchyService _hierarchy;

  /// Finds all signals whose path matches [pattern].
  List<CliSignal> findSignals(String pattern) {
    final expression = RegExp(pattern, caseSensitive: false);
    final signals = <CliSignal>[];
    void collect(HierarchyOccurrence occurrence) {
      for (final signal in occurrence.signals) {
        final path = signal.path();
        if (expression.hasMatch(path)) {
          signals.add(CliSignal.fromOccurrence(signal));
        }
      }
      occurrence.children.forEach(collect);
    }

    collect(_hierarchy.root);
    signals.sort((left, right) => left.id.compareTo(right.id));
    return signals;
  }

  /// Resolves either a dot-string address or a hierarchy/waveform pathname.
  CliSignal? resolveSignal(String reference) {
    final address =
        _tryParseAddress(reference) ?? _hierarchy.pathnameToAddress(reference);
    if (address == null) {
      return null;
    }
    final signal = _hierarchy.signalByAddress(address);
    return signal == null ? null : CliSignal.fromOccurrence(signal);
  }

  OccurrenceAddress? _tryParseAddress(String reference) {
    if (!RegExp(r'^\d+(\.\d+)*$').hasMatch(reference)) {
      return null;
    }
    return OccurrenceAddress.fromDotString(reference);
  }
}

/// A signal that can be addressed by the waveform CLI.
class CliSignal {
  /// Creates a serializable signal descriptor.
  const CliSignal(
      {required this.id,
      required this.name,
      required this.width,
      this.direction,
      this.address});

  /// Creates a descriptor from an address-assigned hierarchy signal.
  factory CliSignal.fromOccurrence(SignalOccurrence signal) => CliSignal(
      id: signal.path(),
      name: signal.name,
      width: signal.width,
      direction: signal.direction,
      address: signal.address?.toDotString());

  /// Human-readable canonical hierarchy path.
  final String id;

  /// Local signal name.
  final String name;

  /// Signal bit width.
  final int width;

  /// Port direction, when this signal is a port.
  final String? direction;

  /// Stable dot-string [OccurrenceAddress] used on the query wire.
  final String? address;

  /// Converts this signal descriptor to a stable JSON object.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'width': width,
        if (direction != null) 'direction': direction,
        if (address != null) 'address': address
      };
}

/// Directed net traversal over schematic connectivity attached to a netlist.
class SchematicTraversalCli {
  /// Builds a connectivity query facade from Yosys-compatible netlist JSON.
  factory SchematicTraversalCli.fromNetlist(Map<String, dynamic> netlist) {
    final adapter = NetlistSchematicAdapter.fromJson(jsonEncode(netlist));
    return SchematicTraversalCli._(adapter);
  }

  SchematicTraversalCli._(this._adapter);

  final NetlistSchematicAdapter _adapter;

  /// Resolves a signal by dot-string address or hierarchy pathname.
  SignalOccurrence? resolveSignalHandle(String reference) {
    final address = _tryParseAddress(reference) ??
        _adapter.hierarchy.pathnameToAddress(reference);
    return address == null ? null : _adapter.hierarchy.signalByAddress(address);
  }

  /// Returns the endpoints driving [signal].
  CliConnectivity faninSignal(
    SignalOccurrence signal, {
    SchematicTraversalMode mode = SchematicTraversalMode.opaque,
  }) =>
      CliConnectivity(
          direction: 'fanin',
          signal: CliSignal.fromOccurrence(signal),
          endpoints: signal
              .fanin(_adapter.schematic, mode: mode)
              .map(CliConnectivityEndpoint.fromSchematicPort)
              .toList());

  /// Returns the endpoints consuming [signal].
  CliConnectivity fanoutSignal(
    SignalOccurrence signal, {
    SchematicTraversalMode mode = SchematicTraversalMode.opaque,
  }) =>
      CliConnectivity(
          direction: 'fanout',
          signal: CliSignal.fromOccurrence(signal),
          endpoints: signal
              .fanout(_adapter.schematic, mode: mode)
              .map(CliConnectivityEndpoint.fromSchematicPort)
              .toList());

  OccurrenceAddress? _tryParseAddress(String reference) {
    if (!RegExp(r'^\d+(\.\d+)*$').hasMatch(reference)) {
      return null;
    }
    return OccurrenceAddress.fromDotString(reference);
  }
}

/// Serializable connectivity traversal result.
class CliConnectivity {
  /// Creates a connectivity result.
  const CliConnectivity(
      {required this.direction, required this.signal, required this.endpoints});

  /// Direction traversed from [signal]: `fanin` or `fanout`.
  final String direction;

  /// Signal used as the traversal source.
  final CliSignal signal;

  /// Reached schematic endpoints.
  final List<CliConnectivityEndpoint> endpoints;

  /// Converts the result to a JSON-ready object.
  Map<String, dynamic> toJson() => {
        'direction': direction,
        'signal': signal.toJson(),
        'endpoints': endpoints.map((endpoint) => endpoint.toJson()).toList()
      };
}

/// Serializable schematic endpoint reached during a connectivity traversal.
class CliConnectivityEndpoint {
  /// Creates an endpoint descriptor.
  const CliConnectivityEndpoint(
      {required this.nodePath, required this.portId, required this.direction});

  /// Creates an endpoint descriptor from a schematic traversal endpoint.
  factory CliConnectivityEndpoint.fromSchematicPort(
          SchematicPortOccurrence endpoint) =>
      CliConnectivityEndpoint(
          nodePath: endpoint.node.occurrence.path(),
          portId: endpoint.port.id,
          direction: endpoint.port.direction);

  /// Hierarchical path of the node containing the port.
  final String nodePath;

  /// Schematic port identity.
  final String portId;

  /// Direction declared for the endpoint port.
  final String direction;

  /// Converts the endpoint to a JSON-ready object.
  Map<String, dynamic> toJson() =>
      {'nodePath': nodePath, 'portId': portId, 'direction': direction};
}

/// Read-only query facade shared by terminal and AI clients.
class WaveformCli {
  /// Creates a read-only waveform query facade.
  WaveformCli({
    required WaveformDataSource waveforms,
    required Future<List<CliSignal>> Function() loadSignals,
  })  : _waveforms = waveforms,
        _loadSignals = loadSignals;

  final WaveformDataSource _waveforms;
  final Future<List<CliSignal>> Function() _loadSignals;

  /// Returns connection and endpoint information without fetching waveforms.
  Future<Map<String, dynamic>> status() async => {
        'schemaVersion': 1,
        'connected': _waveforms.isConnected,
        'mode': _waveforms.modeDescription,
        'currentTimePs': await _waveforms.getCurrentTime()
      };

  /// Lists signals matching [pattern], interpreted as a case-insensitive regex.
  Future<Map<String, dynamic>> findSignals(String pattern) async {
    final expression = RegExp(pattern, caseSensitive: false);
    final signals = await _loadSignals();
    final matches = signals
        .where((signal) => expression.hasMatch(signal.id))
        .toList()
      ..sort((left, right) => left.id.compareTo(right.id));
    return {
      'schemaVersion': 1,
      'pattern': pattern,
      'signals': matches.map((signal) => signal.toJson()).toList()
    };
  }

  /// Gets the value of [signalId] at or immediately before [timePs].
  Future<Map<String, dynamic>> valueAt(String signalId, int timePs) async {
    final waveforms = await _waveforms
        .getWaveformData(signalIds: [signalId], startTime: 0, endTime: timePs);
    final samples = waveforms
        .expand((waveform) => waveform.data)
        .where((sample) => sample.time <= timePs)
        .toList()
      ..sort((left, right) => left.time.compareTo(right.time));
    final sample = samples.isEmpty ? null : samples.last;
    return {
      'schemaVersion': 1,
      'signal': signalId,
      'timePs': timePs,
      'value': sample?.value,
      'sampleTimePs': sample?.time
    };
  }
}

/// Loads CLI signal metadata from the same hierarchy source as DevTools.
Future<List<CliSignal>> loadCliSignals(TreeDataSource tree) async {
  final root = await tree.evalModuleTree();
  if (root == null) {
    return const [];
  }
  final signals = <CliSignal>[];
  void collect(TreeModel node, String path) {
    for (final signal in [...node.inputs, ...node.outputs]) {
      signals.add(CliSignal(
          id: '$path/${signal.name}',
          name: signal.name,
          width: signal.width,
          direction: signal.direction));
    }
    for (final child in node.children) {
      collect(child, '$path/${child.name}');
    }
  }

  collect(root, root.name);
  signals.sort((left, right) => left.id.compareTo(right.id));
  return signals;
}
