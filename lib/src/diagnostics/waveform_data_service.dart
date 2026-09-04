// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// waveform_service.dart
// Service for exposing waveform data to DevTools via VM Service protocol.
// Parallel to ModuleTree for hierarchy data.
//
// 2026 January
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/sanitizer.dart';
import 'package:rohd/src/utilities/uniquifier.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart';

/// Represents a single value change for a signal.
class ValueChange {
  /// The simulation time of the change.
  final int time;

  /// The new value (as a string, e.g., '0', '1', 'x', '0xFF').
  final String value;

  /// Creates a value change record.
  ValueChange({required this.time, required this.value});

  /// Converts to JSON map.
  Map<String, dynamic> toJson() => {'time': time, 'value': value};
}

/// Represents metadata for a signal being tracked.
class TrackedSignal {
  /// Unique identifier (hierarchical path).
  final String id;

  /// Signal name.
  final String name;

  /// Bit width.
  final int width;

  /// Parent scope ID.
  final String scopeId;

  /// Full hierarchical path.
  final String fullPath;

  /// Direction ('input', 'output', or 'internal').
  final String direction;

  /// Creates tracked signal metadata.
  TrackedSignal({
    required this.id,
    required this.name,
    required this.width,
    required this.scopeId,
    required this.fullPath,
    this.direction = 'internal',
  });

  /// Converts to JSON map.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'width': width,
        'scopeId': scopeId,
        'fullPath': fullPath,
        'direction': direction,
        'type': 'logic',
      };
}

/// `WaveformDataService` implements the Singleton design pattern to track
/// signal value changes during simulation for DevTools inspection.
///
/// This works in parallel with `ModuleTree` for hierarchy data. While
/// ModuleTree provides the structure, WaveformDataService provides the
/// time-series signal values.
///
/// ## Usage
///
/// The service is automatically populated when a legacy `WaveDumper` is
/// created with `enableDevTools: true`. Alternatively, you can manually record
/// value changes:
///
/// ```dart
/// // Initialize with a module
/// WaveformDataService.init(myModule);
///
/// // Record a value change
/// WaveformDataService.instance.recordChange('top/clk', 100, '1');
///
/// // Query data from DevTools via VM service evaluate()
/// final json =
///          WaveformDataService.instance.getWaveformsJSON(['top/clk'], 0, 1000);
/// ```
class WaveformDataService {
  /// Private constructor for singleton.
  WaveformDataService._();

  /// Singleton instance.
  static WaveformDataService get instance => _instance;
  static final _instance = WaveformDataService._();

  /// The root module being tracked (optional, for structure).
  Module? _rootModule;

  /// Current simulation time (updated on each value change).
  int _currentTime = 0;

  /// Monotonic ID for compact waveform service logs.
  int _compactRequestSequence = 0;

  /// Map of signal ID to list of value changes.
  final Map<String, List<ValueChange>> _signalData = {};

  /// Map of signal ID to signal metadata.
  final Map<String, TrackedSignal> _signalMetadata = {};

  /// Map of Logic objects to their signal IDs for fast lookup.
  final Map<Logic, String> _logicToIdMap = {};

  /// Reverse map: signal ID to Logic (for snapshot fallback on untracked
  /// signals whose value was set before listeners were attached).
  final Map<String, Logic> _idToLogicMap = {};

  /// Integer index for each signal ID, enabling compact (int-keyed) transport.
  ///
  /// Built during [_collectSignals]. The reverse lookup is done via
  /// [_signalIndexReverse].  Using integer keys in JSON reduces payload size
  /// by ~88% and string object allocations by ~80%, dramatically lowering
  /// GC pressure on both producer and consumer.
  final Map<String, int> _signalIndex = {};

  /// Reverse map: integer index → signal ID.
  final Map<int, String> _signalIndexReverse = {};

  /// Map from OccurrenceAddress dot-string → signal ID (path).
  ///
  /// Built during [_collectSignals].  Enables compact address-keyed transport
  /// where the client sends hierarchical tree-position addresses.
  final Map<String, String> _addressToSignalId = {};

  /// Reverse map: signal ID → OccurrenceAddress dot-string.
  final Map<String, String> _signalIdToAddress = {};

  // ─── FST-backed storage (Phase 2) ────────────────────────────────────
  //
  // When an FstWriter is attached, historical signal data lives on disk
  // in flushed VcData blocks.  WaveformDataService only keeps unflushed data
  // (the "hot buffer") in memory, dramatically reducing memory usage for
  // long simulations.
  //
  // For VCD mode (no FstWriter attached), the full in-memory cache in
  // [_signalData] is used as before.

  /// The attached FST writer, or null for VCD mode.
  FstWriter? _fstWriter;

  /// The block reader (created when [_fstWriter] is attached).
  FstBlockReader? _fstBlockReader;

  /// Mapping from WaveformDataService signal ID → FST handle index (0-based).
  final Map<String, int> _signalIdToFstHandle = {};

  /// Reverse mapping: FST handle index (0-based) → signal ID.
  final Map<int, String> _fstHandleToSignalId = {};

  /// Whether FST-backed disk storage is active.
  bool get isFstBacked => _fstWriter != null;

  /// Attach an [FstWriter] for FST-backed disk storage.
  ///
  /// When attached, [recordChange] stores data only in the writer's
  /// hot buffer instead of the unbounded in-memory [_signalData] map.
  /// Historical data is read back from flushed VcData blocks on demand.
  ///
  /// [logicToHandle] maps each Logic to its FST signal handle, enabling
  /// the service to route queries to the correct disk-backed signal.
  void attachFstWriter(
    FstWriter writer,
    Map<Logic, FstSignalHandle> logicToHandle,
  ) {
    _fstWriter = writer;
    _fstBlockReader = FstBlockReader(writer.filePath, writer.signalInfoList);

    // Build the signal ID ↔ FST handle mapping
    _signalIdToFstHandle.clear();
    _fstHandleToSignalId.clear();
    for (final entry in logicToHandle.entries) {
      final signalId = _logicToIdMap[entry.key];
      if (signalId != null) {
        final handleIdx = entry.value.handle - 1; // 0-based
        _signalIdToFstHandle[signalId] = handleIdx;
        _fstHandleToSignalId[handleIdx] = signalId;
      }
    }
  }

  /// Whether the service has been initialized.
  bool get isInitialized => _rootModule != null || _signalMetadata.isNotEmpty;

  /// Current simulation time.
  int get currentTime => _currentTime;

  /// Number of signals being tracked.
  int get signalCount => _signalMetadata.length;

  /// Total number of value changes recorded.
  int get totalValueChanges =>
      _signalData.values.fold(0, (sum, list) => sum + list.length);

  /// Returns a snapshot of the signal-path to address mapping.
  ///
  /// The keys are signal paths (e.g. `"Counter/count"`) and the values
  /// are the OccurrenceAddress dot-strings (e.g. `"0"`, `"0.2.4"`).
  Map<String, String> get signalAddressMap =>
      Map.unmodifiable(_signalIdToAddress);

  /// Debug accessor for signal data (for diagnostics only).
  ///
  /// Returns an unmodifiable path-keyed map of recorded value changes.
  Map<String, List<ValueChange>> debugGetSignalData() =>
      Map.unmodifiable(_signalData);

  /// Debug accessor: signal ID to live [Logic] object (for testing only).
  ///
  /// Returns an unmodifiable map from signal path to its [Logic] reference.
  Map<String, Logic> debugGetSignalLogicMap() {
    final result = <String, Logic>{};
    for (final entry in _logicToIdMap.entries) {
      result[entry.value] = entry.key;
    }
    return Map.unmodifiable(result);
  }

  /// Debug accessor: address dot-string to signal ID (for testing only).
  ///
  /// Returns a map from OccurrenceAddress dot-string to signal path.
  Map<String, String> debugGetAddressToIdMap() =>
      Map.unmodifiable(_addressToSignalId);

  /// Initialize the service with a module hierarchy.
  ///
  /// This registers all signals in the module tree for tracking,
  /// and registers VM service extensions for fast DevTools communication.
  /// Call this after the module is built.
  static void init(Module module) {
    instance._rootModule = module;
    instance
      .._collectSignalsFromNetlist(module)
      .._registerServiceExtensions();
  }

  /// Whether [startRecording] has already attached change listeners.
  bool _recordingStarted = false;

  /// Records the current value of every mapped signal and subscribes to
  /// future changes, populating the in-memory store for DevTools queries.
  ///
  /// [init] builds the Logic→id map and registers the service extensions but
  /// deliberately does *not* attach change listeners: the legacy `WaveDumper`
  /// integration attaches its own as it writes the VCD/FST file.  A
  /// standalone producer such as `WaveformService` instead calls this once
  /// after [init], so the live DevTools data is populated without
  /// re-implementing the module-tree traversal already done by [init].
  void startRecording() {
    if (_recordingStarted) {
      return;
    }
    _recordingStarted = true;
    for (final logic in _logicToIdMap.keys) {
      // Record the initial value so the signal isn't empty until first change.
      recordLogicChange(logic, Simulator.time);
      logic.changed.listen((_) => recordLogicChange(logic, Simulator.time));
    }
  }

  /// Clear all recorded data and reset the service.
  void clear() {
    _signalData.clear();
    _signalMetadata.clear();
    _logicToIdMap.clear();
    _idToLogicMap.clear();
    _signalIndex.clear();
    _signalIndexReverse.clear();
    _addressToSignalId.clear();
    _signalIdToAddress.clear();
    _signalIdToFstHandle.clear();
    _fstHandleToSignalId.clear();
    _fstWriter = null;
    _fstBlockReader = null;
    _currentTime = 0;
    _rootModule = null;
    _recordingStarted = false;
  }

  /// Whether service extensions have already been registered.
  bool _extensionsRegistered = false;

  /// Register VM service extensions for fast DevTools communication.
  ///
  /// Service extensions use `callServiceExtension()` instead of `evaluate()`,
  /// which avoids the ~650ms evaluate() overhead.  The extension names follow
  /// the `ext.rohd.*` convention so they are clearly namespaced.
  ///
  /// Registered extensions:
  /// - `ext.rohd.waveformStructure` — module/signal structure (no params)
  /// - `ext.rohd.waveformData` — waveform data in time range
  /// - `ext.rohd.waveformDataSince` — incremental data since a time
  /// - `ext.rohd.waveformDataWithTimepoints` — per-signal incremental data
  /// - `ext.rohd.currentTime` — current simulation time
  void _registerServiceExtensions() {
    if (_extensionsRegistered) {
      return;
    }
    _extensionsRegistered = true;

    // Print the VM service URI so users can connect from DevTools.
    unawaited(
      developer.Service.getInfo().then((info) {
        final uri = info.serverUri;
        if (uri != null) {
          // Surface the URI for users connecting DevTools to this process.
          // ignore: avoid_print
          print('ROHD VM Service URI: $uri');
        }
      }),
    );

    // Structure query (no parameters needed)
    developer.registerExtension(
      'ext.rohd.waveformStructure',
      (method, parameters) async =>
          developer.ServiceExtensionResponse.result(structureJSON),
    );

    // Waveform data in a time range
    // Params: signalIdsJson, startTime, endTime
    // Note: result() requires a JSON *object* string, so we wrap the array.
    developer.registerExtension('ext.rohd.waveformData', (
      method,
      parameters,
    ) async {
      final signalIdsJson = parameters['signalIdsJson'] ?? '[]';
      final startTime = int.tryParse(parameters['startTime'] ?? '0') ?? 0;
      final endTime = int.tryParse(parameters['endTime'] ?? '-1') ?? -1;
      final result = getWaveformsJSON(signalIdsJson, startTime, endTime);
      return developer.ServiceExtensionResponse.result('{"data": $result}');
    });

    // Incremental data since a time
    // Params: signalIdsJson, sinceTime
    // Note: result() requires a JSON *object* string, so we wrap the array.
    developer.registerExtension('ext.rohd.waveformDataSince', (
      method,
      parameters,
    ) async {
      final signalIdsJson = parameters['signalIdsJson'] ?? '[]';
      final sinceTime = int.tryParse(parameters['sinceTime'] ?? '0') ?? 0;
      final result = getDataSinceJSON(signalIdsJson, sinceTime);
      return developer.ServiceExtensionResponse.result('{"data": $result}');
    });

    // Per-signal timepoint data
    // Params: signalTimepointsJson
    // Note: result() requires a JSON *object* string, so we wrap the array.
    developer.registerExtension('ext.rohd.waveformDataWithTimepoints', (
      method,
      parameters,
    ) async {
      final timepointsJson = parameters['signalTimepointsJson'] ?? '{}';
      final result = getDataWithTimepointsJSON(timepointsJson);
      return developer.ServiceExtensionResponse.result('{"data": $result}');
    });

    // Current simulation time
    developer.registerExtension(
      'ext.rohd.currentTime',
      (method, parameters) async => developer.ServiceExtensionResponse.result(
        jsonEncode({'currentTime': _currentTime}),
      ),
    );

    // Snapshot: all signal values at a given time Params: time (required)
    // Returns: {"time": int, "signals": {signalId: {"value": str, "name": str,
    // "width": int, "direction": str?}, ...}}
    developer.registerExtension('ext.rohd.snapshot', (
      method,
      parameters,
    ) async {
      final time = int.tryParse(parameters['time'] ?? '') ?? _currentTime;
      final result = getSnapshotJSON(time);
      return developer.ServiceExtensionResponse.result(result);
    });

    // Signal dictionary: maps integer indices to signal IDs/metadata.
    // Called once after getModuleStructure to establish a shared lookup table.
    // This enables compact int-keyed payloads in snapshot and waveform calls.
    developer.registerExtension(
      'ext.rohd.signalDictionary',
      (method, parameters) async =>
          developer.ServiceExtensionResponse.result(getSignalDictionaryJSON()),
    );

    // Compact snapshot: integer-keyed values only (requires dictionary).
    // Params: time (required)
    // Returns: {"time": int, "v": {"0": "val", "1": "val", ...}}
    developer.registerExtension('ext.rohd.snapshotCompact', (
      method,
      parameters,
    ) async {
      final time = int.tryParse(parameters['time'] ?? '') ?? _currentTime;
      return developer.ServiceExtensionResponse.result(
        getSnapshotCompactJSON(time),
      );
    });

    // Compact waveform data: address-keyed signal data. Params:
    // signalIndicesJson (JSON array of address dot-strings), startTime, endTime
    // Returns: {"data": [{"i": "0.2.4", "d": [{"t": 100, "v": "1"}, ...]},
    // ...]}
    developer.registerExtension('ext.rohd.waveformDataCompact', (
      method,
      parameters,
    ) async {
      final indicesJson = parameters['signalIndicesJson'] ?? '[]';
      final startTime = int.tryParse(parameters['startTime'] ?? '0') ?? 0;
      final endTime = int.tryParse(parameters['endTime'] ?? '-1') ?? -1;
      final result = getWaveformsCompactJSON(indicesJson, startTime, endTime);
      return developer.ServiceExtensionResponse.result('{"data": $result}');
    });

    // Compact waveform data with per-signal timepoints. Params:
    // signalTimepointsJson (JSON map: address dot-string → last timepoint)
    // Returns: {"data": [{"i": "0.2.4", "d": [{"t": 100, "v": "1"}, ...]},
    // ...]}
    developer.registerExtension('ext.rohd.waveformDataWithTimepointsCompact', (
      method,
      parameters,
    ) async {
      final timepointsJson = parameters['signalTimepointsJson'] ?? '{}';
      final result = getDataWithTimepointsCompactJSON(timepointsJson);
      return developer.ServiceExtensionResponse.result('{"data": $result}');
    });
  }

  /// Netlist-guided signal registration.
  ///
  /// Walks the synthesized netlist modules map (the same data the hierarchy
  /// adapter uses) to guarantee address alignment with the client tree.
  /// Falls back to [_collectSignals] when no netlist is available.
  void _collectSignalsFromNetlist(Module module) {
    final synthModules = NetlistService.current?.synthesizedModules
        .cast<String, Map<String, dynamic>>();
    if (synthModules == null || synthModules.isEmpty) {
      _collectSignals(module);
      return;
    }

    final rootInstanceName =
        module.hasBuilt ? module.uniqueInstanceName : module.name;
    final rootDef = module.definitionName;
    if (!synthModules.containsKey(rootDef)) {
      _collectSignals(module);
      return;
    }

    // Phase 1: Walk netlist definitions — register signals with addresses
    // in the exact same order as the hierarchy adapter.
    _registerNetlistInstance(
      synthModules: synthModules,
      definitionName: rootDef,
      instancePath: rootInstanceName,
    );

    // Phase 2: Walk ROHD Module tree — map Logic objects to registered
    // signal paths so that recordLogicChange can find them.
    _mapLogicObjects(module, rootInstanceName);
  }

  /// Recursively walk netlist definitions and register all signals.
  ///
  /// Signal ordering matches [NetlistHierarchyAdapter._parseModule]:
  ///   1. Port signals (from `ports` section, in iteration order)
  ///   2. Non-port, non-hidden netnames (from `netnames`, excluding port
  ///      duplicates, hide_name=1, and $-prefixed auto-generated names)
  ///
  /// Child ordering also matches the hierarchy adapter: every non-primitive
  /// cell receives a sequential child address for recursion; primitive cells
  /// are registered as leaves with port signals.
  void _registerNetlistInstance({
    required Map<String, Map<String, dynamic>> synthModules,
    required String definitionName,
    required String instancePath,
    OccurrenceAddress moduleAddress = OccurrenceAddress.root,
  }) {
    final definition = synthModules[definitionName];
    if (definition == null) {
      return;
    }

    final ports = definition['ports'] as Map<String, dynamic>? ?? {};
    final netnames = definition['netnames'] as Map<String, dynamic>? ?? {};
    final portNames = ports.keys.toSet();
    var signalIndex = 0;

    // Register port signals (with addresses).
    for (final entry in ports.entries) {
      final signalName = entry.key;
      final portData = entry.value as Map<String, dynamic>;
      final bits = portData['bits'] as List<dynamic>? ?? [];
      final dir = (portData['direction'] as String?) ?? 'inout';

      final signalPath = '$instancePath/$signalName';
      final addr = moduleAddress.signal(signalIndex++);
      _signalMetadata[signalPath] = TrackedSignal(
        id: signalPath,
        name: signalName,
        width: bits.length,
        scopeId: instancePath,
        fullPath: signalPath,
        direction: dir,
      );
      _signalData[signalPath] = [];
      final addrStr = addr.toDotString();
      _addressToSignalId[addrStr] = signalPath;
      _signalIdToAddress[signalPath] = addrStr;
      final idx = _signalIndex.length;
      _signalIndex[signalPath] = idx;
      _signalIndexReverse[idx] = signalPath;
    }

    // Register non-port, non-hidden netnames (with addresses).
    for (final entry in netnames.entries) {
      final signalName = entry.key;
      if (portNames.contains(signalName)) {
        continue;
      }
      final signalInfo = entry.value as Map<String, dynamic>;
      final hideNameRaw = signalInfo['hide_name'];
      final hideName = hideNameRaw == 1 || hideNameRaw == '1';
      if (hideName || signalName.startsWith(r'$')) {
        continue;
      }

      final bits = signalInfo['bits'] as List<dynamic>? ?? [];
      final signalPath = '$instancePath/$signalName';
      if (_signalMetadata.containsKey(signalPath)) {
        continue;
      }

      final addr = moduleAddress.signal(signalIndex++);
      _signalMetadata[signalPath] = TrackedSignal(
        id: signalPath,
        name: signalName,
        width: bits.length,
        scopeId: instancePath,
        fullPath: signalPath,
      );
      _signalData[signalPath] = [];
      final addrStr = addr.toDotString();
      _addressToSignalId[addrStr] = signalPath;
      _signalIdToAddress[signalPath] = addrStr;
      final idx = _signalIndex.length;
      _signalIndex[signalPath] = idx;
      _signalIndexReverse[idx] = signalPath;
    }

    // Recurse into cells (children).
    final cells = definition['cells'] as Map<String, dynamic>? ?? {};
    var childIndex = 0;
    for (final cellEntry in cells.entries) {
      final cellName = cellEntry.key;
      final cellInfo = cellEntry.value as Map<String, dynamic>;
      final cellType = cellInfo['type'] as String?;
      if (cellType == null) {
        continue;
      }

      final childAddress = moduleAddress.child(childIndex++);

      if (synthModules.containsKey(cellType) &&
          !HierarchyOccurrence.isPrimitiveType(cellType)) {
        // Expandable module — recurse.
        _registerNetlistInstance(
          synthModules: synthModules,
          definitionName: cellType,
          instancePath: '$instancePath/$cellName',
          moduleAddress: childAddress,
        );
      } else {
        // Primitive cell — register port signals as leaf signals.
        final portDirs =
            cellInfo['port_directions'] as Map<String, dynamic>? ?? {};
        final connections =
            cellInfo['connections'] as Map<String, dynamic>? ?? {};

        var portIndex = 0;
        for (final portEntry in portDirs.entries) {
          final portName = portEntry.key;
          final portDir = portEntry.value as String;
          final connBits = connections[portName] as List<dynamic>? ?? [];

          final signalPath = '$instancePath/$cellName/$portName';
          if (_signalMetadata.containsKey(signalPath)) {
            continue;
          }

          final portAddress = childAddress.signal(portIndex++);
          _signalMetadata[signalPath] = TrackedSignal(
            id: signalPath,
            name: portName,
            width: connBits.length,
            scopeId: '$instancePath/$cellName',
            fullPath: signalPath,
            direction: portDir,
          );
          _signalData[signalPath] = [];
          final addrStr = portAddress.toDotString();
          _addressToSignalId[addrStr] = signalPath;
          _signalIdToAddress[signalPath] = addrStr;
          final idx = _signalIndex.length;
          _signalIndex[signalPath] = idx;
          _signalIndexReverse[idx] = signalPath;
        }
      }
    }
  }

  /// Walk ROHD Module tree to map Logic objects to registered signal paths.
  ///
  /// This enables [recordLogicChange] to find the signal ID for each Logic.
  void _mapLogicObjects(Module module, String instancePath) {
    // Map port Logic objects.
    for (final entry in module.inputs.entries) {
      _tryMapLogic(entry.value, '$instancePath/${entry.key}');
      // Also map struct elements.
      if (entry.value is LogicStructure && entry.value is! LogicArray) {
        _mapStructElements(entry.value as LogicStructure, instancePath);
      }
    }
    for (final entry in module.outputs.entries) {
      _tryMapLogic(entry.value, '$instancePath/${entry.key}');
      if (entry.value is LogicStructure && entry.value is! LogicArray) {
        _mapStructElements(entry.value as LogicStructure, instancePath);
      }
    }

    // Map internal Logic objects.
    for (final sig in module.signals) {
      if (module.inputs.containsValue(sig) ||
          module.outputs.containsValue(sig)) {
        continue;
      }
      final name = module.namer.signalNameOfBest([sig]);
      final path = '$instancePath/$name';
      if (_tryMapLogic(sig, path) && sig is Const) {
        // Constants never fire .changed — record their fixed value now.
        recordLogicChange(sig, 0);
      }
    }

    // Recurse into non-InlineSV submodules.
    for (final sub in module.subModules) {
      if (sub is InlineSystemVerilog) {
        continue;
      }
      final subName = sub.hasBuilt ? sub.uniqueInstanceName : sub.name;
      _mapLogicObjects(sub, '$instancePath/$subName');
    }
  }

  /// Map a Logic to a signal path if that path was registered.
  /// Returns true if the mapping was added.
  bool _tryMapLogic(Logic logic, String signalPath) {
    if (_signalMetadata.containsKey(signalPath)) {
      _logicToIdMap[logic] = signalPath;
      _idToLogicMap[signalPath] = logic;
      return true;
    }
    return false;
  }

  /// Map LogicStructure elements to their qualified signal paths.
  void _mapStructElements(LogicStructure struct, String instancePath) {
    for (final element in struct.elements) {
      final qualifiedName = Sanitizer.sanitizeSV(element.structureName);
      _tryMapLogic(element, '$instancePath/$qualifiedName');
      if (element is LogicStructure && element is! LogicArray) {
        _mapStructElements(element, instancePath);
      }
    }
  }

  /// Legacy module-walk signal collection (fallback when no netlist).
  void _collectSignals(
    Module module, [
    String parentPath = '',
    OccurrenceAddress moduleAddress = OccurrenceAddress.root,
  ]) {
    final moduleName = module.name;
    final modulePath =
        parentPath.isEmpty ? moduleName : '$parentPath/$moduleName';

    var signalIndex = 0;

    for (final entry in module.inputs.entries) {
      _registerSignal(
        logic: entry.value,
        name: entry.key,
        scopeId: modulePath,
        direction: 'input',
        hierarchyAddress: moduleAddress.signal(signalIndex++),
      );
    }

    for (final entry in module.outputs.entries) {
      _registerSignal(
        logic: entry.value,
        name: entry.key,
        scopeId: modulePath,
        direction: 'output',
        hierarchyAddress: moduleAddress.signal(signalIndex++),
      );
    }

    final uniquifier = Uniquifier(
      reservedNames: {...module.inputs.keys, ...module.outputs.keys},
    );
    for (final sig in module.signals) {
      if (!module.inputs.containsValue(sig) &&
          !module.outputs.containsValue(sig)) {
        final name = uniquifier.getUniqueName(initialName: sig.name);
        _registerSignal(
          logic: sig,
          name: name,
          scopeId: modulePath,
          direction: 'internal',
          hierarchyAddress: moduleAddress.signal(signalIndex++),
        );
      }
    }

    var childIndex = 0;
    for (final subModule in module.subModules) {
      _collectSignals(subModule, modulePath, moduleAddress.child(childIndex++));
    }
  }

  /// Register a signal for tracking.
  void _registerSignal({
    required Logic logic,
    required String name,
    required String scopeId,
    required String direction,
    OccurrenceAddress? hierarchyAddress,
  }) {
    final fullPath = '$scopeId/$name';
    final id = fullPath;

    _signalMetadata[id] = TrackedSignal(
      id: id,
      name: name,
      width: logic.width,
      scopeId: scopeId,
      fullPath: fullPath,
      direction: direction,
    );

    _signalData[id] = [];
    _logicToIdMap[logic] = id;
    _idToLogicMap[id] = logic;

    // Assign a stable integer index for compact JSON transport.
    final idx = _signalIndex.length;
    _signalIndex[id] = idx;
    _signalIndexReverse[idx] = id;

    // Store the hierarchy address mapping for address-keyed transport.
    if (hierarchyAddress != null) {
      final addrStr = hierarchyAddress.toDotString();
      _addressToSignalId[addrStr] = id;
      _signalIdToAddress[id] = addrStr;
    }
    // Don't record initial value here - signals may not be driven yet.
    // WaveDumper._writeScope() will record initial values at the right time.
  }

  /// Register a signal for tracking.
  ///
  /// [signalId] is the hierarchical path (e.g., 'top/counter/count').
  /// [time] is the simulation time.
  /// [value] is the new value as a string.
  ///
  /// In VCD mode (no FST writer attached), the change is stored in the
  /// in-memory [_signalData] map. If there's already an entry at the same
  /// timestamp, it is replaced (like VCD viewers show the latest value).
  ///
  /// In FST mode, the change is **not** stored in [_signalData] because
  /// the [FstWriter] keeps the hot buffer and flushed blocks on disk.
  /// This eliminates unbounded memory growth for long simulations.
  void recordChange(String signalId, int time, String value) {
    _currentTime = time > _currentTime ? time : _currentTime;

    // In FST mode, skip in-memory storage — the FstWriter holds the hot
    // buffer and flushed blocks on disk.  Query methods read from there.
    if (isFstBacked) {
      return;
    }

    _signalData.putIfAbsent(signalId, () => []);
    final changes = _signalData[signalId]!;

    // Replace existing entry at same time, or append new entry
    if (changes.isNotEmpty && changes.last.time == time) {
      changes[changes.length - 1] = ValueChange(time: time, value: value);
    } else {
      changes.add(ValueChange(time: time, value: value));
    }
  }

  /// Record a value change for a Logic object.
  ///
  /// This is the preferred method when called from WaveDumper.
  void recordLogicChange(Logic logic, int time) {
    final signalId = _logicToIdMap[logic];
    if (signalId == null) {
      return;
    }

    final value = _formatLogicValue(logic);
    recordChange(signalId, time, value);

    // Debug logging disabled to reduce noise.
    // The WaveformDataService maintains a separate in-memory copy of waveforms
    // for DevTools queries (parallel to WaveDumper which writes to file).
    // This is necessary because DevTools needs a queryable API.
  }

  /// Format a Logic value as a string suitable for JSON.
  String _formatLogicValue(Logic logic) {
    final value = logic.value;
    if (logic.width == 1) {
      return value.toString(includeWidth: false);
    } else if (!value.isValid) {
      // Handle invalid values (x, z) by showing the full representation
      return value.toString(includeWidth: false);
    } else {
      // Format as hex for valid multi-bit signals
      // Use toBigInt() to handle values larger than 64 bits
      final hexStr = value.toBigInt().toRadixString(16).toUpperCase();
      return '0x$hexStr';
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FST-backed query helpers
  //
  // These methods read historical data from flushed VcData blocks on disk
  // and merge with the FstWriter's unflushed hot buffer.  Used by the JSON
  // APIs when [isFstBacked] is true.
  // ─────────────────────────────────────────────────────────────────────────

  /// Query FST-backed signal data for [signalId] in time range
  /// [startTime] .. [endTime].
  ///
  /// Reads flushed VcData blocks from disk via [_fstBlockReader] and
  /// unflushed changes from [_fstWriter]'s hot buffer, merging them into
  /// a sorted list of [ValueChange]s.
  List<ValueChange> _queryFstSignal(
    String signalId,
    int startTime,
    int endTime,
  ) {
    final handleIdx = _signalIdToFstHandle[signalId];
    if (handleIdx == null) {
      return [];
    }

    final writer = _fstWriter!;
    final reader = _fstBlockReader!;
    final blocks = writer.blockIndex;
    final result = <ValueChange>[];

    // 1. Read from flushed blocks that overlap [startTime, endTime].
    for (final block in blocks) {
      if (block.endTime < startTime || block.startTime > endTime) {
        continue;
      }

      final changes = reader.readBlock(
        block,
        handleIndices: {handleIdx},
        startTime: startTime,
        endTime: endTime,
      );

      final signalChanges = changes[handleIdx];
      if (signalChanges != null) {
        for (final c in signalChanges) {
          result.add(ValueChange(time: c.time, value: c.value));
        }
      }
    }

    // 2. Read from hot buffer (unflushed changes after last block).
    final hotChanges = writer.queryHotBuffer(handleIdx, startTime, endTime);
    for (final c in hotChanges) {
      result.add(ValueChange(time: c.time, value: c.value));
    }

    // Blocks are chronological and hot buffer is after all blocks, so the
    // result is already sorted.  Sort defensively in case of overlap.
    result.sort((a, b) => a.time.compareTo(b.time));

    return result;
  }

  /// Get the value of an FST-backed signal at-or-before [time].
  ///
  /// Searches the hot buffer first (most recent), then flushed blocks from
  /// newest to oldest.  Falls back to block frame values (carry-over state
  /// at block start) when no explicit change is found.
  String? _getValueAtTimeFst(String signalId, int time) {
    final handleIdx = _signalIdToFstHandle[signalId];
    if (handleIdx == null) {
      return null;
    }

    final writer = _fstWriter!;
    final reader = _fstBlockReader!;
    final blocks = writer.blockIndex;

    // 1. Check hot buffer (unflushed changes after last flushed block).
    final hotChanges = writer.queryHotBuffer(handleIdx, 0, time);
    if (hotChanges.isNotEmpty) {
      return hotChanges.last.value;
    }

    // 2. Search flushed blocks from newest to oldest.
    for (var i = blocks.length - 1; i >= 0; i--) {
      final block = blocks[i];
      if (block.startTime > time) {
        continue;
      }

      // Read all changes for this signal up to `time`.
      final changes = reader.readBlock(
        block,
        handleIndices: {handleIdx},
        endTime: time,
      );

      final signalChanges = changes[handleIdx];
      if (signalChanges != null && signalChanges.isNotEmpty) {
        return signalChanges.last.value;
      }

      // No explicit changes — use the frame carry-over value.
      final frame = reader.readBlockFrame(block);
      return frame[handleIdx];
    }

    // 3. No data found — signal is in its initial/undriven state.
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // JSON API for DevTools (called via VM Service evaluate())
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns the module structure as JSON (signal metadata, no waveform data).
  ///
  /// This is used by DevTools to discover available signals.
  String get structureJSON {
    if (_rootModule == null && _signalMetadata.isEmpty) {
      return jsonEncode({
        'status': 'fail',
        'reason': 'WaveformDataService not initialized',
      });
    }

    final modules = <Map<String, dynamic>>[];

    // Group signals by scope
    final signalsByScope = <String, List<TrackedSignal>>{};
    for (final signal in _signalMetadata.values) {
      signalsByScope.putIfAbsent(signal.scopeId, () => []);
      signalsByScope[signal.scopeId]!.add(signal);
    }

    // Build module structure from scopes
    for (final entry in signalsByScope.entries) {
      modules.add({
        'id': entry.key,
        'name': entry.key.split('/').last,
        'kind': 'HierarchyKind.module',
        'type': entry.key.split('/').last,
        'signals': entry.value.map((s) => s.toJson()).toList(),
        'children': <Map<String, dynamic>>[],
      });
    }

    return jsonEncode({
      'metadata': {
        'source': 'WaveformDataService',
        'timescale': '1ps',
        'date': DateTime.now().toIso8601String(),
        'startTime': 0,
        'endTime': _currentTime,
      },
      'modules': modules,
    });
  }

  /// Returns waveform data for specified signals in a time range.
  ///
  /// [signalIdsJson] is a JSON-encoded list of signal IDs.
  /// [startTime] is the start of the time range (inclusive).
  /// [endTime] is the end of the time range (-1 means current time).
  String getWaveformsJSON(String signalIdsJson, int startTime, int endTime) {
    final signalIds =
        (jsonDecode(signalIdsJson) as List<dynamic>).cast<String>();
    final end = endTime < 0 ? _currentTime : endTime;

    developer.log(
      'getWaveformsJSON: requested=${signalIds.length} ids=$signalIds '
      'timeRange=[$startTime..$end] '
      'knownSignals=${_signalData.length}',
      name: 'WaveformDataService',
    );

    final result = <Map<String, dynamic>>[];

    for (final signalId in signalIds) {
      List<Map<String, dynamic>> filteredData;

      if (isFstBacked) {
        // FST mode: read from disk blocks + hot buffer.
        filteredData = _queryFstSignal(
          signalId,
          startTime,
          end,
        ).map((c) => c.toJson()).toList();
      } else {
        // VCD mode: read from in-memory cache.
        final changes = _signalData[signalId] ?? [];
        filteredData = changes
            .where((c) => c.time >= startTime && c.time <= end)
            .map((c) => c.toJson())
            .toList();
      }

      final found = isFstBacked
          ? _signalIdToFstHandle.containsKey(signalId)
          : _signalData.containsKey(signalId);

      developer.log(
        '  signalId="$signalId" found=$found '
        'filtered=${filteredData.length} fstBacked=$isFstBacked',
        name: 'WaveformDataService',
      );

      if (!found) {
        final known = isFstBacked
            ? _signalIdToFstHandle.keys.take(5).toList()
            : _signalData.keys.take(5).toList();
        developer.log(
          '    NOT FOUND — known IDs (first 5): $known',
          name: 'WaveformDataService',
        );
      }

      result.add({'signalId': signalId, 'data': filteredData});
    }

    return jsonEncode(result);
  }

  /// Returns incremental waveform data since a given time.
  ///
  /// [signalIdsJson] is a JSON-encoded list of signal IDs.
  /// [sinceTime] is the time after which to return data.
  String getDataSinceJSON(String signalIdsJson, int sinceTime) {
    final signalIds =
        (jsonDecode(signalIdsJson) as List<dynamic>).cast<String>();

    final result = <Map<String, dynamic>>[];

    for (final signalId in signalIds) {
      List<Map<String, dynamic>> filteredData;

      if (isFstBacked) {
        filteredData = _queryFstSignal(
          signalId,
          sinceTime,
          _currentTime,
        ).map((c) => c.toJson()).toList();
      } else {
        final changes = _signalData[signalId] ?? [];
        filteredData = changes
            .where((c) => c.time >= sinceTime)
            .map((c) => c.toJson())
            .toList();
      }

      result.add({'signalId': signalId, 'data': filteredData});
    }

    return jsonEncode(result);
  }

  /// Returns incremental waveform data using per-signal timepoints.
  ///
  /// This enables selective waveform transmission where each signal can have a
  /// different last-fetched timepoint. This is used for lazy-loading and
  /// handling dynamic signal addition/removal in the DevTools UI.
  ///
  /// [signalTimepointsJson] is a JSON-encoded map of signal ID -> last
  /// timepoint. Only data points after each signal's timepoint are returned.
  String getDataWithTimepointsJSON(String signalTimepointsJson) {
    final timepointsMap =
        jsonDecode(signalTimepointsJson) as Map<String, dynamic>;

    // Convert string keys and values to proper types
    final signalTimepoints = <String, int>{};
    for (final entry in timepointsMap.entries) {
      final timepoint = entry.value;
      signalTimepoints[entry.key] =
          (timepoint is int) ? timepoint : int.parse(timepoint.toString());
    }

    final result = <Map<String, dynamic>>[];

    for (final entry in signalTimepoints.entries) {
      final signalId = entry.key;
      final sinceTime = entry.value;

      List<Map<String, dynamic>> filteredData;

      if (isFstBacked) {
        // sinceTime is exclusive (> not >=), so use sinceTime + 1 as start.
        filteredData = _queryFstSignal(
          signalId,
          sinceTime + 1,
          _currentTime,
        ).map((c) => c.toJson()).toList();
      } else {
        final changes = _signalData[signalId] ?? [];
        filteredData = changes
            .where((c) => c.time > sinceTime)
            .map((c) => c.toJson())
            .toList();
      }

      result.add({'signalId': signalId, 'data': filteredData});
    }

    return jsonEncode(result);
  }

  /// Returns a snapshot of all signal values at the given [time].
  ///
  /// For each tracked signal, finds the value at-or-before [time] using
  /// binary search. Returns a JSON object:
  /// ```json
  /// {
  ///   "time": 500,
  ///   "signals": {
  ///     "top/counter/clk": {"value": "1", "name": "clk", "width": 1, "direction": "input"},
  ///     ...
  ///   }
  /// }
  /// ```
  String getSnapshotJSON(int time) {
    final signals = <String, Map<String, dynamic>>{};

    if (isFstBacked) {
      // FST mode: iterate over all tracked signals and query disk + hot
      // buffer for the value at-or-before `time`.
      for (final signalId in _signalIdToFstHandle.keys) {
        final metadata = _signalMetadata[signalId];
        final value = _getValueAtTimeFst(signalId, time);

        signals[signalId] = {
          'value': value ?? 'x',
          'name': metadata?.name ?? signalId.split('/').last,
          'width': metadata?.width ?? 1,
          if (metadata?.direction != null) 'direction': metadata!.direction,
        };
      }
    } else {
      // VCD mode: in-memory binary search.
      for (final entry in _signalData.entries) {
        final signalId = entry.key;
        final changes = entry.value;
        final metadata = _signalMetadata[signalId];

        // Binary search for value at-or-before time
        String? value;
        if (changes.isNotEmpty) {
          var lo = 0;
          var hi = changes.length - 1;
          var res = -1;
          while (lo <= hi) {
            final mid = (lo + hi) >> 1;
            if (changes[mid].time <= time) {
              res = mid;
              lo = mid + 1;
            } else {
              hi = mid - 1;
            }
          }
          if (res != -1) {
            value = changes[res].value;
          }
        }

        signals[signalId] = {
          'value': value ?? 'x',
          'name': metadata?.name ?? signalId.split('/').last,
          'width': metadata?.width ?? 1,
          if (metadata?.direction != null) 'direction': metadata!.direction,
        };
      }
    }

    return jsonEncode({'time': time, 'signals': signals});
  }

  /// Returns a list of all tracked signal IDs.
  String get signalIdsJSON => jsonEncode(_signalMetadata.keys.toList());

  /// Returns metadata for all tracked signals.
  String get signalMetadataJSON =>
      jsonEncode(_signalMetadata.values.map((s) => s.toJson()).toList());

  // ─────────────────────────────────────────────────────────────────────────
  // Compact (address-keyed) JSON APIs
  //
  // These use OccurrenceAddress dot-strings instead of full signal-path
  // strings as JSON keys, reducing payload size and enabling direct tree
  // navigation on the consumer side.
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns the signal dictionary: an ordered list of
  /// `{address, id, name, width, direction}` entries.
  ///
  /// ```json
  /// {
  ///   "signals": [
  ///     {"i": "0", "id": "top/clk", "name": "clk", "width": 1,
  ///      "direction": "input"},
  ///     {"i": "0.1", "id": "top/counter/q", "name": "q", "width": 8,
  ///      "direction": "output"},
  ///     ...
  ///   ]
  /// }
  /// ```
  String getSignalDictionaryJSON() {
    final signals = <Map<String, dynamic>>[];
    for (final entry in _signalIdToAddress.entries) {
      final signalId = entry.key;
      final addrStr = entry.value;
      final meta = _signalMetadata[signalId];
      signals.add({
        'i': addrStr,
        'id': signalId,
        'name': meta?.name ?? signalId.split('/').last,
        'width': meta?.width ?? 1,
        'direction': meta?.direction ?? 'internal',
      });
    }
    return jsonEncode({'signals': signals});
  }

  /// Compact snapshot: address-keyed values only.
  ///
  /// ```json
  /// {"time": 500, "v": {"0.2.4": "1", "0.3.1": "0xFF", ...}}
  /// ```
  ///
  /// The consumer resolves each address key back to a signal ID using the
  /// hierarchy tree (OccurrenceAddress navigation).
  String getSnapshotCompactJSON(int time) {
    final values = <String, String>{};

    if (isFstBacked) {
      // FST mode: query disk + hot buffer for each signal.
      for (final entry in _signalIdToFstHandle.entries) {
        final signalId = entry.key;
        final addrStr = _signalIdToAddress[signalId];
        if (addrStr == null) {
          continue;
        }

        final value = _getValueAtTimeFst(signalId, time) ?? 'x';
        values[addrStr] = value;
      }
    } else {
      // VCD mode: in-memory binary search.
      for (final entry in _signalData.entries) {
        final signalId = entry.key;
        final changes = entry.value;
        final addrStr = _signalIdToAddress[signalId];
        if (addrStr == null) {
          continue;
        }
        if (changes.isEmpty) {
          // No recorded changes — the signal was set before listeners were
          // attached (e.g. constant arrays).  Fall back to the live Logic
          // value if a Logic reference is available.
          final logic = _idToLogicMap[signalId];
          if (logic != null) {
            values[addrStr] = _formatLogicValue(logic);
          }
          continue;
        }

        var value = 'x';
        var lo = 0;
        var hi = changes.length - 1;
        var res = -1;
        while (lo <= hi) {
          final mid = (lo + hi) >> 1;
          if (changes[mid].time <= time) {
            res = mid;
            lo = mid + 1;
          } else {
            hi = mid - 1;
          }
        }
        if (res != -1) {
          value = changes[res].value;
        }

        values[addrStr] = value;
      }
    }

    return jsonEncode({'time': time, 'v': values});
  }

  /// Compact waveform data: address-keyed signal data.
  ///
  /// [signalAddressesJson] is a JSON-encoded list of dot-separated
  /// [OccurrenceAddress] strings (e.g. `["0.2.4", "0.3.1"]`).
  ///
  /// ```json
  /// [{"i": "0.2.4", "d": [{"t": 100, "v": "1"}, ...]}, ...]
  /// ```
  ///
  /// Uses short keys (`i` for address, `d` for data array, `t` for time,
  /// `v` for value) to minimise payload size.
  String getWaveformsCompactJSON(
    String signalAddressesJson,
    int startTime,
    int endTime,
  ) {
    final requestId = ++_compactRequestSequence;
    final addresses =
        (jsonDecode(signalAddressesJson) as List<dynamic>).cast<String>();
    final end = endTime < 0 ? _currentTime : endTime;
    final knownSignals =
        isFstBacked ? _signalIdToFstHandle.length : _signalData.length;

    developer.log(
      '[$requestId] getWaveformsCompactJSON: '
      'requested=${addresses.length} addresses, '
      'timeRange=[$startTime..$end], '
      'currentTime=$_currentTime, fstBacked=$isFstBacked, '
      'knownAddresses=${_addressToSignalId.length}, '
      'knownSignals=$knownSignals, '
      'sample=${addresses.take(5).toList()}',
      name: 'WaveformDataService.compact',
    );

    final result = <Map<String, dynamic>>[];
    final missingAddresses = <String>[];
    final emptySignals = <String>[];
    var totalPoints = 0;

    for (final addrStr in addresses) {
      final signalId = _addressToSignalId[addrStr];
      if (signalId == null) {
        missingAddresses.add(addrStr);
        continue;
      }

      List<Map<String, dynamic>> filteredData;

      if (isFstBacked) {
        filteredData = _queryFstSignal(
          signalId,
          startTime,
          end,
        ).map((c) => <String, dynamic>{'t': c.time, 'v': c.value}).toList();
      } else {
        final changes = _signalData[signalId] ?? [];
        filteredData = changes
            .where((c) => c.time >= startTime && c.time <= end)
            .map((c) => <String, dynamic>{'t': c.time, 'v': c.value})
            .toList();
      }

      totalPoints += filteredData.length;
      if (filteredData.isEmpty) {
        emptySignals.add('$addrStr->$signalId');
      }
      result.add({'i': addrStr, 'd': filteredData});
    }

    developer.log(
      '[$requestId] getWaveformsCompactJSON result: '
      'rows=${result.length}, points=$totalPoints, '
      'missingAddresses=${missingAddresses.length}, '
      'emptyMappedSignals=${emptySignals.length}',
      name: 'WaveformDataService.compact',
    );
    if (missingAddresses.isNotEmpty) {
      developer.log(
        '[$requestId] missing compact addresses sample: '
        '${missingAddresses.take(10).toList()}',
        name: 'WaveformDataService.compact',
      );
    }
    if (emptySignals.isNotEmpty) {
      developer.log(
        '[$requestId] mapped compact signals with no data sample: '
        '${emptySignals.take(10).toList()}',
        name: 'WaveformDataService.compact',
      );
    }

    return jsonEncode(result);
  }

  /// Compact waveform data with per-signal timepoints (address-keyed).
  ///
  /// [signalTimepointsJson] is a JSON-encoded map of address dot-string →
  /// last timepoint.
  ///
  /// ```json
  /// [{"i": "0.2.4", "d": [{"t": 200, "v": "0"}, ...]}, ...]
  /// ```
  String getDataWithTimepointsCompactJSON(String signalTimepointsJson) {
    final requestId = ++_compactRequestSequence;
    final timepointsMap =
        jsonDecode(signalTimepointsJson) as Map<String, dynamic>;
    final knownSignals =
        isFstBacked ? _signalIdToFstHandle.length : _signalData.length;

    developer.log(
      '[$requestId] getDataWithTimepointsCompactJSON: '
      'requested=${timepointsMap.length} addresses, '
      'currentTime=$_currentTime, fstBacked=$isFstBacked, '
      'knownAddresses=${_addressToSignalId.length}, '
      'knownSignals=$knownSignals, '
      'sample=${timepointsMap.keys.take(5).toList()}',
      name: 'WaveformDataService.compact',
    );

    final result = <Map<String, dynamic>>[];
    final missingAddresses = <String>[];
    final emptySignals = <String>[];
    var totalPoints = 0;

    for (final entry in timepointsMap.entries) {
      final addrStr = entry.key;
      final sinceTime = (entry.value is int)
          ? entry.value as int
          : int.parse(entry.value.toString());

      final signalId = _addressToSignalId[addrStr];
      if (signalId == null) {
        missingAddresses.add(addrStr);
        continue;
      }

      List<Map<String, dynamic>> filteredData;

      if (isFstBacked) {
        filteredData = _queryFstSignal(
          signalId,
          sinceTime + 1,
          _currentTime,
        ).map((c) => <String, dynamic>{'t': c.time, 'v': c.value}).toList();
      } else {
        final changes = _signalData[signalId] ?? [];
        filteredData = changes
            .where((c) => c.time > sinceTime)
            .map((c) => <String, dynamic>{'t': c.time, 'v': c.value})
            .toList();
      }

      totalPoints += filteredData.length;
      if (filteredData.isEmpty) {
        emptySignals.add('$addrStr->$signalId since=$sinceTime');
      }
      result.add({'i': addrStr, 'd': filteredData});
    }

    developer.log(
      '[$requestId] getDataWithTimepointsCompactJSON result: '
      'rows=${result.length}, points=$totalPoints, '
      'missingAddresses=${missingAddresses.length}, '
      'emptyMappedSignals=${emptySignals.length}',
      name: 'WaveformDataService.compact',
    );
    if (missingAddresses.isNotEmpty) {
      developer.log(
        '[$requestId] missing compact timepoint addresses sample: '
        '${missingAddresses.take(10).toList()}',
        name: 'WaveformDataService.compact',
      );
    }
    if (emptySignals.isNotEmpty) {
      developer.log(
        '[$requestId] mapped compact timepoint signals with no data sample: '
        '${emptySignals.take(10).toList()}',
        name: 'WaveformDataService.compact',
      );
    }

    return jsonEncode(result);
  }
}
