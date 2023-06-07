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

  List<Conditional> conditionalDriveOther(
          Interface<TagType> other, Iterable<TagType> tags) =>
      getPorts(tags)
          .map((portName, thisPort) =>
              MapEntry(portName, other.port(portName) < thisPort))
          .values
          .toList();

  List<Conditional> conditionalReceiveOther(
          Interface<TagType> other, Iterable<TagType> tags) =>
      getPorts(tags)
          .map((portName, thisPort) =>
              MapEntry(portName, thisPort < other.port(portName)))
          .values
          .toList();
}

// TODO(mkorbel1): addSubInterface type of function

enum PairDirection { fromProvider, fromConsumer, sharedInputs }

enum PairRole { provider, consumer, monitor }

class PairInterface extends Interface<PairDirection> {
  String Function(String original)? uniquify;

  /// TODO(): fix doc
  PairInterface({
    List<Port>? portsFromConsumer,
    List<Port>? portsFromProvider,
    List<Port>? sharedInputPorts,
    this.uniquify,
  }) {
    //TODO: accept a list of subinterfaces that are also PairInterface?
    if (portsFromConsumer != null) {
      setPorts(portsFromConsumer, [PairDirection.fromConsumer]);
    }
    if (portsFromProvider != null) {
      setPorts(portsFromProvider, [PairDirection.fromProvider]);
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
            portsFromProvider:
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
    Set<PairDirection> inputTags;
    Set<PairDirection> outputTags;

    switch (role) {
      case PairRole.consumer:
        inputTags = {
          PairDirection.sharedInputs,
          PairDirection.fromProvider,
        };
        outputTags = {
          PairDirection.fromConsumer,
        };
        break;

      case PairRole.provider:
        inputTags = {
          PairDirection.sharedInputs,
          PairDirection.fromConsumer,
        };
        outputTags = {
          PairDirection.fromProvider,
        };
        break;

      case PairRole.monitor:
        inputTags = {
          PairDirection.sharedInputs,
          PairDirection.fromConsumer,
          PairDirection.fromProvider,
        };
        outputTags = {};
    }

    connectIO(module, srcInterface,
        inputTags: inputTags, outputTags: outputTags, uniquify: uniquify);
  }

  @override
  void connectIO(Module module, Interface<dynamic> srcInterface,
      {Iterable<PairDirection>? inputTags,
      Iterable<PairDirection>? outputTags,
      String Function(String original)? uniquify}) {
    super.connectIO(module, srcInterface,
        inputTags: inputTags, outputTags: outputTags, uniquify: uniquify);

    uniquify ??= (original) => original;

    if (subInterfaces.isNotEmpty) {
      if (srcInterface is! PairInterface) {
        throw Exception(
            'Sub interfaces but not connecting to pair interface'); //TODO
      }

      // srcInterface as PairInterface;

      for (final subInterfaceEntry in _subInterfaces.values) {
        final subInterface = subInterfaceEntry.interface;
        final subInterfaceName = subInterfaceEntry.name;
        final subInterfaceUniquify =
            subInterface.uniquify ?? (original) => original;

        if (!srcInterface._subInterfaces.containsKey(subInterfaceName)) {
          throw Exception(
              'no corresponding sub interface $subInterfaceName'); //TODO
        }

        // handle possible reversal as best as we can
        Iterable<PairDirection>? subIntfInputTags;
        Iterable<PairDirection>? subIntfOutputTags;
        if (subInterfaceEntry.reverse) {
          // swap consumer tag
          if (inputTags?.contains(PairDirection.fromConsumer) ?? false) {
            subIntfOutputTags = {PairDirection.fromConsumer};
          }
          if (outputTags?.contains(PairDirection.fromConsumer) ?? false) {
            subIntfInputTags = {PairDirection.fromConsumer};
          }

          // swap provider tag
          if (outputTags?.contains(PairDirection.fromProvider) ?? false) {
            subIntfInputTags = {PairDirection.fromProvider};
          }
          if (inputTags?.contains(PairDirection.fromProvider) ?? false) {
            subIntfOutputTags = {PairDirection.fromProvider};
          }

          // keep sharedInputs, if it's there
          if (inputTags?.contains(PairDirection.sharedInputs) ?? false) {
            subIntfInputTags = {
              if (subIntfInputTags != null) ...subIntfInputTags,
              PairDirection.sharedInputs,
            };
          }
        } else {
          subIntfInputTags = inputTags;
          subIntfOutputTags = outputTags;
        }

        subInterface.connectIO(
          module,
          srcInterface._subInterfaces[subInterfaceName]!.interface,
          inputTags: subIntfInputTags,
          outputTags: subIntfOutputTags,
          uniquify: (original) => uniquify!(
            subInterfaceUniquify(original),
          ),
        );
      }
    }
  }

  Map<String, PairInterface> get subInterfaces =>
      UnmodifiableMapView(_subInterfaces
          .map((name, subInterface) => MapEntry(name, subInterface.interface)));

  final Map<String, _SubPairInterface> _subInterfaces = {};

  @protected
  PairInterfaceType addSubInterface<PairInterfaceType extends PairInterface>(
    String name,
    PairInterfaceType subInterface, {
    bool reverse = false,
  }) {
    if (_subInterfaces.containsKey(name)) {
      throw Exception('subintf name not unique'); //TODO
    }

    if (!Sanitizer.isSanitary(name)) {
      throw Exception('Invalid name'); //TODO
    }

    _subInterfaces[name] = _SubPairInterface(name, subInterface, reverse);
    return subInterface;
  }
}

class _SubPairInterface<PairInterfaceType extends PairInterface> {
  final String name;
  final PairInterfaceType interface;
  final bool reverse;
  _SubPairInterface(this.name, this.interface, this.reverse);
}
