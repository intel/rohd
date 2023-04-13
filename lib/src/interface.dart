/// Copyright (C) 2021 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// interface.dart
/// Definitions for interfaces and ports
///
/// 2021 May 25
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/sanitizer.dart';

/// An extension of [Logic] useful for [Interface] definitions.
class Port extends Logic {
  /// Constructs a [Logic] intended to be used for ports in an [Interface].
  Port(String name, [int width = 1]) : super(name: name, width: width) {
    if (!Sanitizer.isSanitary(name)) {
      throw Exception(
          'Invalid name "$name", must be legal SystemVerilog and not collide'
          ' with any keywords.');
    }
  }
}

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
            // ignore: invalid_use_of_protected_member
            module.addInput(
              uniquify(port.name),
              srcInterface.port(port.name),
              width: port.width,
            );
      }
    }

    if (outputTags != null) {
      for (final port in getPorts(outputTags).values) {
        // ignore: invalid_use_of_protected_member
        final output = module.addOutput(uniquify(port.name), width: port.width);
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

  /// Makes `this` drive interface signals tagged as [direction] on [other].
  void driveOther(Interface<TagType> other, Iterable<TagType> tags) {
    getPorts(tags).forEach((portName, thisPort) {
      other.port(portName) <= thisPort;
    });
  }

  void receiveOther(Interface<TagType> other, Iterable<TagType> tags) {
    getPorts(tags).forEach((portName, thisPort) {
      thisPort <= other.port(portName);
    });
  }

  // TODO: what about driving all ports on an interface to some value instead of another instance of an interface?

  List<ConditionalAssign> conditionalDriveOther(
          Interface<TagType> other, Iterable<TagType> tags) =>
      getPorts(tags)
          .map((portName, thisPort) =>
              MapEntry(portName, other.port(portName) < thisPort))
          .values
          .toList();

  List<ConditionalAssign> conditionalReceiveOther(
          Interface<TagType> other, Iterable<TagType> tags) =>
      getPorts(tags)
          .map((portName, thisPort) =>
              MapEntry(portName, thisPort < other.port(portName)))
          .values
          .toList();
}

// TODO(mkorbel1): addSubInterface type of function

enum PairDirection { fromProvider, fromConsumer, sharedInputs }

enum PairRole { provider, consumer }

class PairInterface extends Interface<PairDirection> {
  /// TODO(): fix doc
  PairInterface(
      {List<Port>? portsFromConsumer,
      List<Port>? portsFromProducer,
      List<Port>? sharedInputPorts}) {
    //TODO: accept a list of subinterfaces that are also PairInterface?
    if (portsFromConsumer != null) {
      setPorts(portsFromConsumer, [PairDirection.fromConsumer]);
    }
    if (portsFromProducer != null) {
      setPorts(portsFromProducer, [PairDirection.fromProvider]);
    }
    if (sharedInputPorts != null) {
      setPorts(sharedInputPorts, [PairDirection.sharedInputs]);
    }
  }

  static List<Port> _getMatchPorts(
          Interface<PairDirection> otherInterface, PairDirection tag) =>
      otherInterface
          .getPorts({tag})
          .entries
          .map((e) => Port(e.key, e.value.width))
          .toList();

  PairInterface.clone(Interface<PairDirection> otherInterface)
      : this(
            portsFromConsumer:
                _getMatchPorts(otherInterface, PairDirection.fromConsumer),
            portsFromProducer:
                _getMatchPorts(otherInterface, PairDirection.fromProvider),
            sharedInputPorts:
                _getMatchPorts(otherInterface, PairDirection.sharedInputs));

  // TODO: driveOther could be on Interface in general?
  // TODO: could add receiveOther as well, for opposite direction?
  // TODO: conditional versions of those

  //TODO: name things consistently, why simple sometimes, pair others

  void simpleConnectIO(
      Module module, Interface<PairDirection> srcInterface, PairRole role,
      {String Function(String original)? uniquify}) {
    connectIO(module, srcInterface,
        inputTags: {
          PairDirection.sharedInputs,
          if (role == PairRole.provider)
            PairDirection.fromConsumer
          else
            PairDirection.fromProvider
        },
        outputTags: role == PairRole.consumer
            ? {PairDirection.fromConsumer}
            : {PairDirection.fromProvider},
        uniquify: uniquify);

    // for(final subInterface in _subInterfaces) {
    //   subInterface.interface.connectIO(module, srcInterface)
    // }
  }

  final Map<String, _SubInterface> _subInterfaces = {};

  @protected
  void addSubInterface<T>(
    String name,
    Interface<T> subInterface,
    _SimpleConnectFunction<T> connectSubInterface,
  ) {
    _subInterfaces[name] =
        (_SubInterface<T>(name, subInterface, connectSubInterface));
  }

  @protected
  void addSubPairInterface(String name, PairInterface subInterface) =>
      addSubInterface(name, subInterface, simpleConnectIO);
}

enum SharedInputConnectionMode { dontConnect, thisDrivesOther, otherDrivesThis }

class _SubInterface<T> {
  final String name;
  final Interface<T> interface;
  final _SimpleConnectFunction<T> connect;
  _SubInterface(this.name, this.interface, this.connect);
}

typedef _SimpleConnectFunction<T> = void Function(
    Module module, Interface<T> srcInterface, PairRole dir,
    {String Function(String original)? uniquify});
