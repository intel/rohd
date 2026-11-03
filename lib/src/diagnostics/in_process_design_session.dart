// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// in_process_design_session.dart
// In-process implementation of the public ROHD design session API.
//
// 2026 August
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/src/diagnostics/design_session.dart';
import 'package:rohd/src/diagnostics/waveform_data_service.dart';
import 'package:rohd/src/synthesizers/netlist/netlist_service.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart';

/// A [RohdDesignSession] backed directly by a synthesized [NetlistService].
///
/// This implementation is appropriate for target-side consumers. Transport
/// adapters should use the opaque IDs and values returned here rather than
/// exposing hierarchy occurrences across process boundaries.
class InProcessRohdDesignSession
    implements RohdDesignSession, RohdSynchronousDesignSession {
  /// Creates a session for an already synthesized [netlist].
  InProcessRohdDesignSession(this.netlist, {RohdDesignEpoch? epoch})
      : _epoch = epoch ?? const RohdDesignEpoch(0);

  /// Netlist used by this session.
  final NetlistService netlist;
  final RohdDesignEpoch _epoch;

  @override
  HierarchyService get hierarchy => netlist.hierarchy;

  @override
  Future<RohdDesignStatus> status() async => statusNow();

  @override
  RohdDesignStatus statusNow() => RohdDesignStatus(
        epoch: _epoch,
        designName: netlist.module.definitionName,
        capabilities: {
          RohdDesignCapability.hierarchy,
          RohdDesignCapability.connectivity,
          if (WaveformDataService.instance.isInitialized)
            RohdDesignCapability.waveform,
        },
      );

  @override
  Future<HierarchyOccurrence?> findCell(String path) async => findCellNow(path);

  @override
  HierarchyOccurrence? findCellNow(String path) => _occurrenceByShellPath(path);

  @override
  Future<SignalOccurrence?> findSignal(String path) async =>
      findSignalNow(path);

  @override
  SignalOccurrence? findSignalNow(String path) {
    final parts = _shellPathParts(path);
    if (parts.isEmpty) {
      return null;
    }
    final signalName = parts.removeLast();
    final owner = parts.isEmpty
        ? hierarchy.root
        : hierarchy.occurrenceByPathname(parts.join('/'));
    final signalIndex = owner?.signalIndexByName(signalName) ?? -1;
    return owner == null || signalIndex < 0 ? null : owner.signals[signalIndex];
  }

  @override
  Future<SignalOccurrence?> findPort(String path) async => findPortNow(path);

  @override
  SignalOccurrence? findPortNow(String path) {
    final parts = _shellPathParts(path);
    if (parts.isEmpty) {
      return null;
    }
    final portName = parts.removeLast();
    final owner = parts.isEmpty
        ? hierarchy.root
        : hierarchy.occurrenceByPathname(parts.join('/'));
    return owner?.portByName(portName);
  }

  HierarchyOccurrence? _occurrenceByShellPath(String path) {
    final parts = _shellPathParts(path);
    return parts.isEmpty
        ? hierarchy.root
        : hierarchy.occurrenceByPathname(parts.join('/'));
  }

  List<String> _shellPathParts(String path) {
    final parts =
        path.split(RegExp(r'[/\.]')).where((part) => part.isNotEmpty).toList();
    if (parts.isNotEmpty && _isTopLevelName(parts.first)) {
      parts.removeAt(0);
    }
    return parts;
  }

  bool _isTopLevelName(String name) =>
      name == hierarchy.root.name ||
      name == hierarchy.root.definition ||
      name == netlist.module.definitionName;

  @override
  Future<List<String>> completeCellPaths(
    String prefix, {
    int limit = 20,
  }) async =>
      completeCellPathsNow(prefix, limit: limit);

  @override
  List<String> completeCellPathsNow(String prefix, {int limit = 20}) =>
      _completeShellPaths(prefix, limit, hierarchy.autocompletePaths);

  @override
  Future<List<String>> completeSignalPaths(
    String prefix, {
    int limit = 20,
  }) async =>
      completeSignalPathsNow(prefix, limit: limit);

  @override
  List<String> completeSignalPathsNow(String prefix, {int limit = 20}) =>
      _completeShellPaths(prefix, limit, hierarchy.autocompleteSignalPaths);

  @override
  Future<List<String>> completePortPaths(
    String prefix, {
    int limit = 20,
  }) async =>
      completePortPathsNow(prefix, limit: limit);

  @override
  List<String> completePortPathsNow(String prefix, {int limit = 20}) =>
      _completeShellPaths(prefix, limit, hierarchy.autocompletePortPaths);

  List<String> _completeShellPaths(
    String prefix,
    int limit,
    List<String> Function(String, {int? limit}) complete,
  ) {
    final rootDefinition =
        hierarchy.root.definition ?? netlist.module.definitionName;
    final parts = prefix.split(RegExp(r'[/\.]+'));
    if (!rootDefinition.startsWith(parts.first)) {
      return complete(prefix, limit: limit);
    }
    parts[0] = hierarchy.root.name;
    return complete(parts.join('/'), limit: limit)
        .map((path) => path.replaceFirst(hierarchy.root.name, rootDefinition))
        .toList();
  }

  @override
  Future<RohdPage<HierarchyOccurrence>> findCells(
    String pattern, {
    HierarchyOccurrence? root,
    bool transparent = false,
    RohdQueryOptions options = const RohdQueryOptions(),
  }) async =>
      findCellsNow(
        pattern,
        root: root,
        transparent: transparent,
        options: options,
      );

  @override
  RohdPage<HierarchyOccurrence> findCellsNow(
    String pattern, {
    HierarchyOccurrence? root,
    bool transparent = false,
    RohdQueryOptions options = const RohdQueryOptions(),
  }) =>
      _page(
        _matchingCells(
          hierarchy,
          root ?? hierarchy.root,
          pattern,
          transparent: transparent,
          limit: _searchLimit(options),
        ),
        options,
      );

  @override
  Future<RohdPage<SignalOccurrence>> findSignals(
    String pattern, {
    HierarchyOccurrence? root,
    bool transparent = false,
    RohdQueryOptions options = const RohdQueryOptions(),
  }) async =>
      findSignalsNow(
        pattern,
        root: root,
        transparent: transparent,
        options: options,
      );

  @override
  RohdPage<SignalOccurrence> findSignalsNow(
    String pattern, {
    HierarchyOccurrence? root,
    bool transparent = false,
    RohdQueryOptions options = const RohdQueryOptions(),
  }) =>
      _page(
        _matchingPorts(
          hierarchy,
          root ?? hierarchy.root,
          pattern,
          transparent: transparent,
          limit: _searchLimit(options),
        ),
        options,
      );

  @override
  Future<RohdPage<SignalOccurrence>> findPorts(
    String pattern, {
    HierarchyOccurrence? root,
    bool transparent = false,
    RohdQueryOptions options = const RohdQueryOptions(),
  }) async =>
      findPortsNow(
        pattern,
        root: root,
        transparent: transparent,
        options: options,
      );

  @override
  RohdPage<SignalOccurrence> findPortsNow(
    String pattern, {
    HierarchyOccurrence? root,
    bool transparent = false,
    RohdQueryOptions options = const RohdQueryOptions(),
  }) =>
      _page(
        _matchingSignals(
          hierarchy,
          root ?? hierarchy.root,
          pattern,
          transparent: transparent,
          limit: _searchLimit(options),
        ).where((signal) => signal.isPort),
        options,
      );

  @override
  Future<RohdPage<SignalOccurrence>> fanin(
    SignalOccurrence signal, {
    bool transparent = false,
    RohdQueryOptions options = const RohdQueryOptions(),
  }) async =>
      faninNow(signal, transparent: transparent, options: options);

  @override
  RohdPage<SignalOccurrence> faninNow(
    SignalOccurrence signal, {
    bool transparent = false,
    RohdQueryOptions options = const RohdQueryOptions(),
  }) =>
      _page(netlist.fanin(signal, transparent: transparent), options);

  @override
  Future<RohdPage<SignalOccurrence>> fanout(
    SignalOccurrence signal, {
    bool transparent = false,
    RohdQueryOptions options = const RohdQueryOptions(),
  }) async =>
      fanoutNow(signal, transparent: transparent, options: options);

  @override
  RohdPage<SignalOccurrence> fanoutNow(
    SignalOccurrence signal, {
    bool transparent = false,
    RohdQueryOptions options = const RohdQueryOptions(),
  }) =>
      _page(netlist.fanout(signal, transparent: transparent), options);

  @override
  Future<RohdSignalValue> getSignalValue(
    SignalOccurrence signal, {
    int? time,
  }) async =>
      getSignalValueNow(signal, time: time);

  @override
  RohdSignalValue getSignalValueNow(SignalOccurrence signal, {int? time}) {
    final address = signal.address;
    if (address == null) {
      throw StateError('Signal occurrence has no address.');
    }
    final waveform = WaveformDataService.instance;
    final sampled = waveform.valueAtAddress(address, time: time);
    return RohdSignalValue(
      signal: signal,
      time: sampled.time,
      value: sampled.value,
      sampleTime: sampled.sampleTime,
    );
  }

  static Iterable<HierarchyOccurrence> _matchingCells(
    HierarchyService hierarchy,
    HierarchyOccurrence root,
    String pattern, {
    required bool transparent,
    required int limit,
  }) sync* {
    for (final path in hierarchy.searchOccurrencePathsRegex(
      _scopedPattern(root, pattern),
      limit: limit,
    )) {
      final occurrence = hierarchy.occurrenceByPathname(path);
      if (occurrence == null) {
        continue;
      }
      if ((!transparent || occurrence.children.isEmpty) &&
          _isDescendantOf(occurrence, root)) {
        yield occurrence;
      }
    }
  }

  static Iterable<SignalOccurrence> _matchingSignals(
    HierarchyService hierarchy,
    HierarchyOccurrence root,
    String pattern, {
    required bool transparent,
    required int limit,
  }) sync* {
    for (final path in hierarchy.searchSignalPathsRegex(
      _scopedPattern(root, pattern),
      limit: limit,
    )) {
      final signal = _signalByPath(hierarchy, path);
      if (signal != null &&
          (!transparent || signal.parent!.children.isEmpty) &&
          _isDescendantOf(signal.parent!, root)) {
        yield signal;
      }
    }
  }

  static Iterable<SignalOccurrence> _matchingPorts(
    HierarchyService hierarchy,
    HierarchyOccurrence root,
    String pattern, {
    required bool transparent,
    required int limit,
  }) sync* {
    var searchLimit = limit;
    var examined = 0;
    var yielded = 0;
    while (yielded < limit) {
      final paths = hierarchy.searchSignalPathsRegex(
        _scopedPattern(root, pattern),
        limit: searchLimit,
      );
      for (final path in paths.skip(examined)) {
        final signal = _signalByPath(hierarchy, path);
        if (signal != null &&
            signal.isPort &&
            (!transparent || signal.parent!.children.isEmpty) &&
            _isDescendantOf(signal.parent!, root)) {
          yield signal;
          yielded++;
          if (yielded == limit) {
            return;
          }
        }
      }
      if (paths.length < searchLimit) {
        return;
      }
      examined = paths.length;
      searchLimit *= 2;
    }
  }

  static SignalOccurrence? _signalByPath(
    HierarchyService hierarchy,
    String path,
  ) {
    final separator = path.lastIndexOf('/');
    if (separator < 0) {
      return null;
    }
    final owner = hierarchy.occurrenceByPathname(path.substring(0, separator));
    final signalName = path.substring(separator + 1);
    final index = owner?.signalIndexByName(signalName) ?? -1;
    return index < 0 ? null : owner!.signals[index];
  }

  static bool _isDescendantOf(
    HierarchyOccurrence occurrence,
    HierarchyOccurrence root,
  ) {
    for (HierarchyOccurrence? current = occurrence;
        current != null;
        current = current.parent) {
      if (identical(current, root)) {
        return true;
      }
    }
    return false;
  }

  static String _scopedPattern(HierarchyOccurrence root, String pattern) {
    final expression = pattern.contains('/') ? pattern : '**/$pattern';
    if (root.parent == null) {
      return expression;
    }
    final rootPath = root.path().split('/').map(RegExp.escape).join('/');
    return '$rootPath/$expression';
  }

  static int _searchLimit(RohdQueryOptions options) {
    if (options.pageSize < 1) {
      throw ArgumentError.value(
        options.pageSize,
        'pageSize',
        'Must be positive.',
      );
    }
    final offset =
        options.pageToken == null ? 0 : int.tryParse(options.pageToken!);
    if (offset == null || offset < 0) {
      throw ArgumentError.value(
        options.pageToken,
        'pageToken',
        'Must be a non-negative offset.',
      );
    }
    return offset + options.pageSize + 1;
  }

  static RohdPage<T> _page<T>(Iterable<T> values, RohdQueryOptions options) {
    if (options.pageSize < 1) {
      throw ArgumentError.value(
        options.pageSize,
        'pageSize',
        'Must be positive.',
      );
    }
    final offset =
        options.pageToken == null ? 0 : int.tryParse(options.pageToken!);
    if (offset == null || offset < 0) {
      throw ArgumentError.value(
        options.pageToken,
        'pageToken',
        'Must be a non-negative offset.',
      );
    }
    final iterator = values.iterator;
    for (var index = 0; index < offset; index++) {
      if (!iterator.moveNext()) {
        throw ArgumentError.value(
          options.pageToken,
          'pageToken',
          'Exceeds result count.',
        );
      }
    }
    final items = <T>[];
    while (items.length < options.pageSize && iterator.moveNext()) {
      items.add(iterator.current);
    }
    final hasMore = iterator.moveNext();
    return RohdPage(
      items: items,
      nextPageToken: hasMore ? (offset + items.length).toString() : null,
    );
  }
}
