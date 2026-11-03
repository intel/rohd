// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// waveform_repository.dart
// Domain layer that manages the retrieval of signal waveforms.
//
// 2024 January 29
// Author(s): Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
//            Yao Jing Quek <yao.jing.quek@intel.com>

import 'dart:async';

import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_waveform/rohd_waveform.dart';

export 'signal_data_service_impl.dart';

/// A class that manages the retrieval of signal waveforms.
///
/// It uses an instance of [SignalWaveformApi] to retrieve the data.
/// Maintains a cache of [SignalOccurrence] metadata and a separate cache of
/// [SignalWaveform] objects for waveform data.
class SignalWaveformRepository {
  /// Currently selected module, if any.
  HierarchyOccurrence? selectedModule;

  /// The [SignalWaveformApi] instance used to retrieve the data.
  SignalWaveformApi _signalWaveformApi;

  /// Hierarchy service for tree-walk pathname ↔ address conversions.
  /// Set via [hierarchyService] after loading a hierarchy.
  HierarchyService? hierarchyService;

  /// Optional future that completes when the underlying API is ready.
  ///
  /// On web, the Wellen WASM may need to finish loading the waveform bytes
  /// before calls to the underlying API succeed. Passing a readiness future
  /// allows repository methods to wait for that event. Tests and native
  /// usage may leave this null.
  Future<void>? _apiReady;

  /// A cache of signal metadata keyed by [OccurrenceAddress].
  final Map<OccurrenceAddress, SignalOccurrence> _signalCache = {};

  /// A cache of signal waveform data keyed by [OccurrenceAddress].
  final Map<OccurrenceAddress, SignalWaveform> _waveformCache = {};

  /// Fallback cache for computed sub-field waveforms (e.g. bit-slices of
  /// arrays/structs) that don't have a real [OccurrenceAddress] in the
  /// hierarchy tree.  Keyed by the raw signal ID string.
  final Map<String, SignalWaveform> _subFieldWaveformCache = {};

  /// Expose the API for file loading operations
  SignalWaveformApi get api => _signalWaveformApi;

  /// Creates a new instance of [SignalWaveformRepository].
  ///
  /// Requires [signalWaveformApi] as a parameter.
  SignalWaveformRepository({
    required SignalWaveformApi signalWaveformApi,
    Future<void>? apiReady,
  })  : _signalWaveformApi = signalWaveformApi,
        _apiReady = apiReady {
    // Register the signal lookup function so SignalWaveform can resolve
    // metadata.
    // Uses tree-walk to convert signalId strings to addresses for cache lookup.
    SignalWaveform.signalLookup = _lookupSignalByPath;
  }

  /// Look up a [SignalOccurrence] by its pathname string.
  /// Used as the [SignalWaveform] backpointer lookup function.
  SignalOccurrence? _lookupSignalByPath(String signalId) {
    final addr = hierarchyService?.pathnameToAddress(signalId);
    return addr != null ? _signalCache[addr] : null;
  }

  /// Replace the underlying API at runtime (e.g., switch from mock to Wellen
  /// when the user picks a file). Clears cached signals and waveform data.
  void setSignalWaveformApi(
    SignalWaveformApi signalWaveformApi, {
    Future<void>? apiReady,
  }) {
    _signalWaveformApi = signalWaveformApi;
    _apiReady = apiReady;
    clearSignalCache();
    clearAllWaveformData();
  }

  Future<void>? _waitForApiLoaded({
    Duration timeout = const Duration(seconds: 10),
  }) {
    final api = _signalWaveformApi;
    if (api.isLoaded) {
      return Future.value();
    }

    final completer = Completer<void>();
    final deadline = DateTime.now().add(timeout);

    void poll() {
      if (api.isLoaded) {
        completer.complete();
        return;
      }

      if (DateTime.now().isAfter(deadline)) {
        completer.complete();
        return;
      }

      Future.delayed(const Duration(milliseconds: 50), poll);
    }

    poll();
    return completer.future;
  }

  /// Internal helper to wait for API readiness if provided.
  Future<void> _ensureReady() async {
    if (_apiReady != null) {
      final loadedFuture = _waitForApiLoaded();
      if (loadedFuture != null) {
        await Future.any([_apiReady!, loadedFuture]);
      } else {
        await _apiReady;
      }
    }
  }

  /// Proactively expand all slim module definitions for client-side
  /// evaluation.  Delegates to [SignalWaveformApi.expandAllSlimModules].
  Future<void> expandAllSlimModules() =>
      _signalWaveformApi.expandAllSlimModules();

  /// Build the signal cache from the given module hierarchy.
  ///
  /// Ensures occurrence addresses are assigned via `buildAddresses()` and
  /// auto-creates a hierarchy service if one hasn't been set explicitly.
  /// Call this after receiving the hierarchy from the external
  /// tree-data-source path, via `setExternalHierarchy` in the bloc.
  void buildSignalCacheFromHierarchy(List<HierarchyOccurrence> modules) {
    final roots = modules.length <= 1
        ? modules
        : [
            HierarchyOccurrence(
              name: 'root',
              definition: 'waveform',
              children: modules,
            ),
          ];
    // Ensure every node and signal has an address.
    for (final m in roots) {
      if (m.address == null) {
        m.buildAddresses();
      }
    }
    // Auto-create a HierarchyService if the caller hasn't set one.
    if (hierarchyService == null && roots.isNotEmpty) {
      hierarchyService = BaseHierarchyAdapter.fromTree(roots.first);
    }
    _buildSignalCache(roots);
  }

  /// Get the current simulation time from the waveform API.
  Future<int?> getCurrentTime() =>
      _ensureReady().then((_) => _signalWaveformApi.getCurrentTime());

  /// Retrieves waveform data for specific signals.
  ///
  /// [signalIds] is a list of signal IDs for which to retrieve data.
  /// [startTime] and [endTime] optionally specify an inclusive time range in
  /// the same units as [Data.time].
  ///
  /// Sub-field IDs (containing `#`) are intercepted and synthesized via
  /// bit-slicing the parent signal's waveform data. This enables sub-field
  /// expansion to work with any API backend (including Wellen/VCD).
  ///
  /// Returns a [Future] that completes with a list of [WaveformData] objects.
  Future<List<WaveformData>> getWaveformData({
    required List<String> signalIds,
    int? startTime,
    int? endTime,
  }) =>
      () async {
        await _ensureReady();

        // Separate plain IDs from sub-field IDs.
        final plainIds = <String>[];
        final subFieldIds = <String>[];
        for (final id in signalIds) {
          if (id.contains(_subFieldSeparator)) {
            subFieldIds.add(id);
          } else {
            plainIds.add(id);
          }
        }

        // Fetch plain signals from the API.
        final results = <WaveformData>[];
        if (plainIds.isNotEmpty) {
          results.addAll(
            await _signalWaveformApi.getWaveformData(
              signalIds: plainIds,
              startTime: startTime,
              endTime: endTime,
            ),
          );
        }

        // Synthesize sub-field bit-slices at the repository level.
        if (subFieldIds.isNotEmpty) {
          for (final sfId in subFieldIds) {
            final synthesized = await _synthesizeBitSlice(
              sfId,
              startTime: startTime,
              endTime: endTime,
            );
            if (synthesized != null) {
              results.add(synthesized);
            }
          }
        }

        return results;
      }();

  /// Loads waveform data for specific signals and appends it to the cached
  /// signals.
  ///
  /// [signalIds] is a list of signal IDs for which to load data.
  /// [startTime] and [endTime] optionally specify a time range for the data.
  /// [sortByTime] if true, sorts the data by time after appending.
  ///
  /// Returns a [Future] that completes with the list of [WaveformData] loaded.
  Future<List<WaveformData>> loadAndAppendWaveformData({
    required List<String> signalIds,
    int? startTime,
    int? endTime,
    bool sortByTime = true,
  }) async {
    final waveformDataList = await getWaveformData(
      signalIds: signalIds,
      startTime: startTime,
      endTime: endTime,
    );
    for (final waveformData in waveformDataList) {
      // Resolve the waveform service signal ID to a OccurrenceAddress
      // via O(depth) tree walk (no maps needed).
      final addr = _resolveWaveformAddress(waveformData.signalId);

      // A null/null range means "full fetch". Replace cached waveform to
      // avoid stale/duplicated points causing misplaced transitions.
      final isFullFetch = startTime == null && endTime == null;

      if (addr == null) {
        // Sub-field / computed waveform — no real address in the tree.
        // Cache by raw string ID.
        final id = waveformData.signalId;
        if (isFullFetch || !_subFieldWaveformCache.containsKey(id)) {
          _subFieldWaveformCache[id] = SignalWaveform.fromWaveformData(
            waveformData,
          );
        } else {
          _subFieldWaveformCache[id]!.appendWaveformData(
            waveformData,
            sortByTime: sortByTime,
          );
        }
        continue;
      }

      final canonicalSignalId =
          hierarchyService!.addressToPathname(addr, asSignal: true) ??
              waveformData.signalId;
      if (isFullFetch || !_waveformCache.containsKey(addr)) {
        _waveformCache[addr] = SignalWaveform.fromWaveformData(
          waveformData,
          signalId: canonicalSignalId,
        );
      } else {
        _waveformCache[addr]!.appendWaveformData(
          waveformData,
          sortByTime: sortByTime,
        );
      }
    }
    return waveformDataList;
  }

  /// Resolve a waveform service signal ID string to a [OccurrenceAddress]
  /// using an O(depth) tree walk.  Returns null when the hierarchy service
  /// is not set or the path doesn't exist in the tree.
  OccurrenceAddress? _resolveWaveformAddress(String waveformSignalId) =>
      hierarchyService?.waveformIdToAddress(waveformSignalId);

  /// Streams waveform data incrementally for specific signals.
  ///
  /// [signalIds] is a list of signal IDs for which to stream data.
  /// [startTime] optionally specifies the starting time for the data stream.
  /// [appendToSignals] if true, automatically appends streamed data to
  /// cached waveforms.
  ///
  /// Returns a [Stream] of [WaveformData] objects.
  Stream<WaveformData> streamWaveformData({
    required List<String> signalIds,
    int? startTime,
    bool appendToSignals = true,
  }) async* {
    await for (final waveformData in _signalWaveformApi.streamWaveformData(
      signalIds: signalIds,
      startTime: startTime,
    )) {
      if (appendToSignals) {
        final addr = _resolveWaveformAddress(waveformData.signalId);
        if (addr != null) {
          final waveform = _waveformCache[addr];
          if (waveform != null) {
            waveform.appendWaveformData(waveformData);
          } else {
            final canonicalSignalId =
                hierarchyService!.addressToPathname(addr, asSignal: true) ??
                    waveformData.signalId;
            _waveformCache[addr] = SignalWaveform.fromWaveformData(
              waveformData,
              signalId: canonicalSignalId,
            );
          }
        } else {
          // Sub-field / computed waveform — cache by string ID.
          final id = waveformData.signalId;
          final waveform = _subFieldWaveformCache[id];
          if (waveform != null) {
            waveform.appendWaveformData(waveformData);
          } else {
            _subFieldWaveformCache[id] = SignalWaveform.fromWaveformData(
              waveformData,
            );
          }
        }
      }
      yield waveformData;
    }
  }

  /// Appends waveform data to a specific signal.
  ///
  /// [signalId] is the ID of the signal to append data to.
  /// [data] is the list of data points to append.
  /// [sortByTime] if true, sorts the data by time after appending.
  ///
  /// Returns true if data was appended (creates waveform if not exists).
  bool appendDataToSignal(
    String signalId,
    List<Data> data, {
    bool sortByTime = false,
  }) {
    final addr = _resolveWaveformAddress(signalId);
    if (addr == null) {
      // Sub-field / computed waveform — cache by string ID.
      var waveform = _subFieldWaveformCache[signalId];
      if (waveform == null) {
        waveform = SignalWaveform.empty(signalId);
        _subFieldWaveformCache[signalId] = waveform;
      }
      waveform.appendData(data, sortByTime: sortByTime);
      return true;
    }

    var waveform = _waveformCache[addr];
    if (waveform == null) {
      waveform = SignalWaveform.empty(signalId);
      _waveformCache[addr] = waveform;
    }
    waveform.appendData(data, sortByTime: sortByTime);
    return true;
  }

  /// Clears waveform data for a specific signal.
  ///
  /// [address] is the address of the signal whose data should be cleared.
  ///
  /// Returns true if the waveform was found and data was cleared.
  bool clearWaveformData(OccurrenceAddress address) {
    final waveform = _waveformCache[address];
    if (waveform != null) {
      waveform.clearData();
      return true;
    }
    return false;
  }

  /// Clears all waveform data from all cached signals.
  void clearAllWaveformData() {
    _waveformCache.clear();
    _subFieldWaveformCache.clear();
  }

  /// Clears the entire signal cache (used when loading a new file).
  void clearSignalCache() {
    _signalCache.clear();
    _waveformCache.clear();
    _subFieldWaveformCache.clear();
  }

  // ───────────── Address-based cache accessors ─────────────────

  /// Gets a signal by its [OccurrenceAddress].  O(1).
  SignalOccurrence? getSignal(OccurrenceAddress address) =>
      _signalCache[address];

  /// Gets a signal waveform by [OccurrenceAddress].  O(1).
  SignalWaveform? getWaveform(OccurrenceAddress address) =>
      _waveformCache[address];

  /// Gets all cached signal addresses.
  List<OccurrenceAddress> get cachedSignalAddresses =>
      _signalCache.keys.toList();

  // ───────────── String convenience accessors (tree-walk) ──────────

  /// Gets a signal by pathname string.  O(depth) tree walk.
  SignalOccurrence? getSignalById(String signalId) =>
      _lookupSignalByPath(signalId);

  /// Gets a signal waveform by pathname string.  O(depth) tree walk.
  /// Falls back to the sub-field cache for computed waveforms (bit-slices).
  SignalWaveform? getWaveformById(String signalId) {
    final addr = hierarchyService?.pathnameToAddress(signalId);
    if (addr != null) {
      return _waveformCache[addr];
    }
    // Fallback: check sub-field cache for computed waveforms.
    return _subFieldWaveformCache[signalId];
  }

  /// Gets all cached signal IDs as pathname strings.
  List<String> get cachedSignalIds =>
      _signalCache.values.map((s) => s.path()).toList();

  /// Gets signals with their waveform data for the selected module.
  List<SignalWaveform> getWaveformsBySelectedModule(
    HierarchyOccurrence module,
  ) {
    final waveforms = <SignalWaveform>[];
    for (final signal in module.signals) {
      final addr = signal.address;
      if (addr == null) {
        continue;
      }
      var waveform = _waveformCache[addr];
      if (waveform == null) {
        waveform = SignalWaveform.empty(signal.path());
        _waveformCache[addr] = waveform;
      }
      waveforms.add(waveform);
    }
    return waveforms;
  }

  /// Gets signal metadata for the selected module.
  ///
  /// Use [getWaveformsBySelectedModule] to get waveform data.
  List<SignalOccurrence> getSignalsBySelectedModule(
    HierarchyOccurrence module,
  ) {
    final signals = <SignalOccurrence>[];
    for (final signal in module.signals) {
      final addr = signal.address;
      if (addr == null) {
        continue;
      }
      if (!_signalCache.containsKey(addr)) {
        _signalCache[addr] = signal;
      }
      signals.add(signal);
    }
    return signals;
  }

  /// Builds the signal cache from the signal hierarchy.
  void _buildSignalCache(List<HierarchyOccurrence> modules) {
    void collectSignals(List<HierarchyOccurrence> nodes) {
      for (final module in nodes) {
        for (final signal in module.signals) {
          final addr = signal.address;
          if (addr == null) {
            continue;
          }
          if (!_signalCache.containsKey(addr)) {
            _signalCache[addr] = signal;
          }
          if (!_waveformCache.containsKey(addr)) {
            _waveformCache[addr] = SignalWaveform.empty(signal.path());
          }
        }
        collectSignals(module.children);
      }
    }

    collectSignals(modules);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Sub-field bit-slice synthesis (API-agnostic)
  // ─────────────────────────────────────────────────────────────────────────

  static const String _subFieldSeparator = '#';

  /// Synthesize waveform data for a sub-field by extracting a bit range
  /// from the parent signal's waveform data.
  ///
  /// Works with any API backend (DevTools, Wellen/VCD) because it fetches the
  /// parent waveform via the API and resolves bit positions from the
  /// hierarchy metadata.
  Future<WaveformData?> _synthesizeBitSlice(
    String signalId, {
    int? startTime,
    int? endTime,
  }) async {
    final pathParts = signalId.split(_subFieldSeparator);
    if (pathParts.length < 2 || pathParts.any((part) => part.isEmpty)) {
      return null;
    }

    final parentPath = pathParts.first;
    final slicePaths = pathParts.skip(1);

    // Resolve parent signal metadata for logicType and width.
    final parentSig = _lookupSignalByPath(parentPath);
    if (parentSig == null) {
      return null;
    }
    final parentWidth = parentSig.width;

    var lo = 0;
    var fieldWidth = parentWidth;
    String? fieldPath;
    var hasBitSlice = false;

    for (final slicePath in slicePaths) {
      final bitSliceMatch =
          RegExp(r'^b\[(\d+)(?::(\d+))?\]$').firstMatch(slicePath);
      if (bitSliceMatch != null) {
        final firstBit = int.parse(bitSliceMatch.group(1)!);
        final secondBit = bitSliceMatch.group(2) != null
            ? int.parse(bitSliceMatch.group(2)!)
            : firstBit;
        final relativeLo = firstBit < secondBit ? firstBit : secondBit;
        final sliceWidth = (firstBit - secondBit).abs() + 1;
        if (hasBitSlice ||
            relativeLo < 0 ||
            relativeLo + sliceWidth > fieldWidth) {
          return null;
        }
        lo += relativeLo;
        fieldWidth = sliceWidth;
        hasBitSlice = true;
        continue;
      }

      if (hasBitSlice || parentSig.logicType == null) {
        return null;
      }
      fieldPath = fieldPath == null ? slicePath : '$fieldPath.$slicePath';
      final resolved = _resolveFieldBits(parentSig.logicType!, fieldPath);
      if (resolved == null) {
        return null;
      }
      lo = resolved.startBit;
      fieldWidth = resolved.width;
    }

    // Fetch parent waveform data from the API.
    final parentData = await _signalWaveformApi.getWaveformData(
      signalIds: [parentPath],
      startTime: startTime,
      endTime: endTime,
    );

    if (parentData.isEmpty || parentData.first.data.isEmpty) {
      return WaveformData(signalId: signalId, data: const []);
    }

    final pData = parentData.first.data;

    // Extract bits at each parent timepoint, deduplicating consecutive values.
    final outputData = <Data>[];
    String? lastValue;

    for (final point in pData) {
      final sliced = _extractBits(point.value, parentWidth, lo, fieldWidth);
      if (sliced != lastValue) {
        outputData.add(Data(time: point.time, value: sliced));
        lastValue = sliced;
      }
    }

    return WaveformData(signalId: signalId, data: outputData, isComputed: true);
  }

  /// Recursively resolve a dot-separated field path within a [logicType] map
  /// to its absolute bit position and width within the parent signal.
  static ({int startBit, int width})? _resolveFieldBits(
    Map<String, dynamic> logicType,
    String fieldPath,
  ) {
    final dotIdx = fieldPath.indexOf('.');
    final String segment;
    final String? remainder;
    if (dotIdx >= 0) {
      segment = fieldPath.substring(0, dotIdx);
      remainder = fieldPath.substring(dotIdx + 1);
    } else {
      segment = fieldPath;
      remainder = null;
    }

    // Struct case: look up named field.
    final fields = logicType['fields'] as List<dynamic>?;
    if (fields != null) {
      for (final fieldRaw in fields) {
        final field = fieldRaw as Map<String, dynamic>;
        final name = field['name'] as String? ?? '';
        if (name != segment) {
          continue;
        }

        final bits = field['bits'] as List<dynamic>?;
        final width = field['width'] as int? ?? 1;
        final startBit = bits != null && bits.isNotEmpty
            ? (bits.cast<int>().reduce((a, b) => a < b ? a : b))
            : 0;

        if (remainder == null) {
          return (startBit: startBit, width: width);
        }
        final nestedType = field['type'] as Map<String, dynamic>?;
        if (nestedType == null) {
          return null;
        }
        final inner = _resolveFieldBits(nestedType, remainder);
        if (inner == null) {
          return null;
        }
        return (startBit: startBit + inner.startBit, width: inner.width);
      }
      return null;
    }

    // Array case: look up by index [N].
    final arrayDims = logicType['arrayDims'] as List<dynamic>?;
    if (arrayDims != null) {
      final leafWidth = (logicType['elementWidth'] as int?) ?? 1;
      final remainingDims =
          arrayDims.length > 1 ? arrayDims.sublist(1).cast<int>() : <int>[];
      final perElementWidth = remainingDims.isEmpty
          ? leafWidth
          : remainingDims.fold<int>(leafWidth, (acc, d) => acc * d);
      final elementType = logicType['elementType'] as Map<String, dynamic>?;

      final match = RegExp(r'^\[(\d+)\]$').firstMatch(segment);
      if (match == null) {
        return null;
      }
      final index = int.parse(match.group(1)!);
      final startBit = index * perElementWidth;

      if (remainder == null) {
        return (startBit: startBit, width: perElementWidth);
      }
      final subType = elementType ??
          (remainingDims.isNotEmpty
              ? <String, dynamic>{
                  'arrayDims': remainingDims,
                  'elementWidth': leafWidth,
                  'width': perElementWidth,
                }
              : null);
      if (subType == null) {
        return null;
      }
      final inner = _resolveFieldBits(subType, remainder);
      if (inner == null) {
        return null;
      }
      return (startBit: startBit + inner.startBit, width: inner.width);
    }

    return null;
  }

  /// Extract [width] bits starting at [startBit] from a value string.
  ///
  /// Handles multiple value formats:
  /// - ROHD LogicValue format: `16'hFF00`, `8'b10101010`
  /// - Raw hex: `ff00`, `0xff00`
  /// - Raw binary: `10101010`
  /// - x/z states
  ///
  /// Returns a sized radix string, using binary when needed to preserve X/Z.
  static String _extractBits(
    String value,
    int parentWidth,
    int startBit,
    int width,
  ) {
    final parentBits = _normalizeFourStateBits(value, parentWidth);
    final sliceStart = parentWidth - startBit - width;
    final sliceEnd = parentWidth - startBit;
    final sliced = parentBits.sublist(sliceStart, sliceEnd);

    if (width == 1) {
      return sliced.single;
    }
    if (sliced.any((bit) => bit == 'x' || bit == 'z')) {
      return "$width'b${sliced.join()}";
    }

    final numeric = BigInt.parse(sliced.join(), radix: 2);
    final hexDigits = (width + 3) ~/ 4;
    final hex = numeric.toRadixString(16).padLeft(hexDigits, '0');
    return "$width'h$hex";
  }

  static List<String> _normalizeFourStateBits(String value, int parentWidth) {
    final lower = value.toLowerCase().trim();
    final rohdMatch = RegExp(r"^(\d+)'([hb])(.+)$").firstMatch(lower);

    List<String>? bits;
    int? literalWidth;
    if (rohdMatch != null) {
      literalWidth = int.tryParse(rohdMatch.group(1)!);
      bits = _decodeFourStateDigits(rohdMatch.group(3)!, rohdMatch.group(2)!);
    } else if (lower.startsWith('0x')) {
      bits = _decodeFourStateDigits(lower.substring(2), 'h');
    } else if (lower.startsWith('0b')) {
      bits = _decodeFourStateDigits(lower.substring(2), 'b');
    } else if (RegExp(r'^[01xz]+$').hasMatch(lower)) {
      bits = _decodeFourStateDigits(lower, 'b');
    } else {
      bits = _decodeFourStateDigits(lower, 'h');
    }

    if (bits == null || literalWidth == 0) {
      return List<String>.filled(parentWidth, 'x');
    }

    if (literalWidth != null) {
      bits = _resizeFourStateBits(bits, literalWidth, extendUnknown: true);
    }
    return _resizeFourStateBits(
      bits,
      parentWidth,
      extendUnknown: literalWidth == null,
    );
  }

  static List<String>? _decodeFourStateDigits(String digits, String radix) {
    if (radix == 'b') {
      return RegExp(r'^[01xz]+$').hasMatch(digits) ? digits.split('') : null;
    }
    if (!RegExp(r'^[0-9a-fxz]+$').hasMatch(digits)) {
      return null;
    }

    return [
      for (final digit in digits.split(''))
        if (digit == 'x' || digit == 'z')
          ...List<String>.filled(4, digit)
        else
          ...int.parse(
            digit,
            radix: 16,
          ).toRadixString(2).padLeft(4, '0').split(''),
    ];
  }

  static List<String> _resizeFourStateBits(
    List<String> bits,
    int width, {
    required bool extendUnknown,
  }) {
    if (bits.length >= width) {
      return bits.sublist(bits.length - width);
    }

    final leadingBit = bits.isEmpty ? 'x' : bits.first;
    final extension = extendUnknown && (leadingBit == 'x' || leadingBit == 'z')
        ? leadingBit
        : '0';
    return [...List<String>.filled(width - bits.length, extension), ...bits];
  }
}
