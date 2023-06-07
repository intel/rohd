// Copyright (C) 2021-2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// interface.dart
// Definitions for interfaces and ports
//
// 2021 May 25
// Author: Max Korbel <max.korbel@intel.com>

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';

/// Represents a logical interface to a [Module].
///
/// Interfaces make it easier to define port connections of a [Module]
/// in a reusable way.  The [TagType] allows grouping of port signals
/// of the module when connecting at a [Module] level.
///
/// When connecting an [Interface] to a [Module], you should always create
/// a new instance of the [Interface] so you don't modify the one being
/// passed in through the constructor.  Modifying the same [Interface] as
/// was passed would have negative consequences if multiple [Module]s
/// were consuming the same [Interface], and also breaks the rules for
/// [Module] input and output connectivity.
class Interface<TagType> {
  /// Internal map from the [Interface]'s defined port name to an instance
  /// of a [Port].
  ///
  /// Note that each port's name (`port.name`) does not necessarily match the
  /// keys of [_ports] if they have been uniquified.
  final Map<String, Logic> _ports = {};

  /// Maps from the [Interface]'s defined port name to an instance of a [Port].
  ///
  /// Note that each port's name (`port.name`) does not necessarily match the
  /// keys of [_ports] if they have been uniquified.
  Map<String, Logic> get ports => UnmodifiableMapView(_ports);

  /// Maps from the [Interface]'s defined port name to the set of tags
  /// associated with that port.
  final Map<String, Set<TagType>> _portToTagMap = {};

  /// Accesses a port named [name].
  ///
  /// This [name] is not a uniquified name, it is the original port name.
  Logic port(String name) => _ports.containsKey(name)
      ? _ports[name]!
      : throw Exception('Port name "$name" not found on this interface.');

  /// Connects [module]'s inputs and outputs up to [srcInterface] and this
  /// [Interface].
  ///
  /// The [srcInterface] should be a new instance of the [Interface] to be used
  /// by [module] for all input and output connectivity.  All signals in the
  /// interface with specified [TagType] will be connected to the [Module] via
  /// [Module.addInput] or [Module.addOutput] based on [inputTags] and
  /// [outputTags], respectively.  [uniquify] can be used to uniquifiy
  /// port names by manipulating the original name of the port.
  ///
  /// If [inputTags] or [outputTags] is not specified, then, respectively,
  /// no inputs or outputs will be added.
  void connectIO(Module module, Interface<dynamic> srcInterface,
      {Iterable<TagType>? inputTags,
      Iterable<TagType>? outputTags,
      String Function(String original)? uniquify}) {
    uniquify ??= (original) => original;

    if (inputTags != null) {
      for (final port in getPorts(inputTags).values) {
        port <=
            (port is LogicArray
                // ignore: invalid_use_of_protected_member
                ? module.addInputArray(
                    port.name,
                    srcInterface.port(port.name),
                    dimensions: port.dimensions,
                    elementWidth: port.elementWidth,
                    numUnpackedDimensions: port.numUnpackedDimensions,
                  )
                // ignore: invalid_use_of_protected_member
                : module.addInput(
                    uniquify(port.name),
                    srcInterface.port(port.name),
                    width: port.width,
                  ));
      }
    }

    if (outputTags != null) {
      for (final port in getPorts(outputTags).values) {
        // ignore: invalid_use_of_protected_member
        final output = (port is LogicArray
            // ignore: invalid_use_of_protected_member
            ? module.addOutputArray(
                port.name,
                dimensions: port.dimensions,
                elementWidth: port.elementWidth,
                numUnpackedDimensions: port.numUnpackedDimensions,
              )
            // ignore: invalid_use_of_protected_member
            : module.addOutput(
                uniquify(port.name),
                width: port.width,
              ));
        output <= port;
        srcInterface.port(port.name) <= output;
      }
    }
  }

  /// Returns all interface ports associated with the provided [tags] as a
  /// [Map] from the port name to the [Logic] port.
  ///
  /// Returns all ports if [tags] is null.
  Map<String, Logic> getPorts([Iterable<TagType>? tags]) {
    if (tags == null) {
      return ports;
    } else {
      final matchingPorts = <String, Logic>{};
      for (final tag in tags.toSet().toList()) {
        matchingPorts.addEntries(_ports.keys
            .where(
                (portName) => _portToTagMap[portName]?.contains(tag) ?? false)
            .map((matchingPortName) =>
                MapEntry(matchingPortName, _ports[matchingPortName]!)));
      }
      return matchingPorts;
    }
  }

  /// Adds a single new port to this [Interface], associated with [tags]
  /// and with name [portName].
  ///
  /// If no [portName] is specified, then [port]'s name is used.
  void _setPort(Logic port, {Iterable<TagType>? tags, String? portName}) {
    portName ??= port.name;

    assert(!_ports.containsKey(portName),
        'Port named $portName already exists on this interface.');

    _ports[portName] = port;
    if (tags != null) {
      if (!_portToTagMap.containsKey(portName)) {
        _portToTagMap[portName] = <TagType>{};
      }
      _portToTagMap[portName]!.addAll(tags);
    }
  }

  /// Adds a collection of ports to this [Interface], each associated with all
  /// of [tags].
  ///
  /// All names of ports are gotten from the names of the [ports].
  @protected
  void setPorts(List<Logic> ports, [Iterable<TagType>? tags]) {
    for (final port in ports) {
      _setPort(port, tags: tags);
    }
  }

  /// Makes `this` drive interface signals tagged with [tags] on [other].
  void driveOther(Interface<TagType> other, Iterable<TagType> tags) {
    getPorts(tags).forEach((portName, thisPort) {
      other.port(portName) <= thisPort;
    });
  }

  /// Makes `this` signals tagged with [tags] be driven by [other].
  void receiveOther(Interface<TagType> other, Iterable<TagType> tags) {
    getPorts(tags).forEach((portName, thisPort) {
      thisPort <= other.port(portName);
    });
  }

  /// Makes `this` conditionally drive interface signals tagged with [tags] on
  /// [other].
  Conditional conditionalDriveOther(
          Interface<TagType> other, Iterable<TagType> tags) =>
      ConditionalGroup(getPorts(tags)
          .map((portName, thisPort) =>
              MapEntry(portName, other.port(portName) < thisPort))
          .values
          .toList());

  /// Makes `this` signals tagged with [tags] be driven conditionally by
  /// [other].
  Conditional conditionalReceiveOther(
          Interface<TagType> other, Iterable<TagType> tags) =>
      ConditionalGroup(getPorts(tags)
          .map((portName, thisPort) =>
              MapEntry(portName, thisPort < other.port(portName)))
          .values
          .toList());
}
