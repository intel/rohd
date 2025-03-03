// Copyright (C) 2023-2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// pair_interface.dart
// Definitions for PairInterafce
//
// 2023 June 7
// Author: Max Korbel <max.korbel@intel.com>

import 'dart:collection';

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/sanitizer.dart';

/// A direction for signals between a pair of components.
enum PairDirection {
  /// Signals driven as outputs by the "provider" in the pair.
  fromProvider,

  /// Signals driven as outputs by the "consumer" in the pair.
  fromConsumer,

  /// Signals that are inputs to both components in the pair.
  sharedInputs,

  /// Signals that are inOuts for both components in the pair.
  commonInOuts,
}

/// The role that a component in a pair plays.
enum PairRole {
  /// The side of the "provider".
  provider,

  /// The side of the "consumer".
  consumer,
}

/// A simplified version of [Interface] which is intended for a common situation
/// where two components are communicating with each other and may share some
/// common inputs.
///
/// It can be either directly used for simple scenarios, or extended for more
/// complex situations.
class PairInterface extends Interface<PairDirection> {
  /// A function that can be used to modify all port names in a certain way.
  String Function(String original)? modify;

  /// Constructs an instance of a [PairInterface] with the specified ports.
  ///
  /// The [modify] function will allow modification of all port names, in
  /// addition to the usual uniquification that can occur during [connectIO].
  PairInterface({
    List<Logic>? portsFromConsumer,
    List<Logic>? portsFromProvider,
    List<Logic>? sharedInputPorts,
    List<Logic>? commonInOutPorts,
    this.modify,
  }) {
    if (portsFromConsumer != null) {
      setPorts(portsFromConsumer, [PairDirection.fromConsumer]);
    }
    if (portsFromProvider != null) {
      setPorts(portsFromProvider, [PairDirection.fromProvider]);
    }
    if (sharedInputPorts != null) {
      setPorts(sharedInputPorts, [PairDirection.sharedInputs]);
    }
    if (commonInOutPorts != null) {
      setPorts(commonInOutPorts, [PairDirection.commonInOuts]);
    }
  }

  /// Collects ports on a given [interface] tagged with [tag].
  static List<Logic> _getMatchPorts(
          Interface<PairDirection> interface, PairDirection tag) =>
      interface
          .getPorts({tag})
          .entries
          .map((e) {
            final p = e.value;
            final name = e.key;
            switch (p) {
              case LogicArray():
                return p.isNet
                    ? LogicArray.netPort(name, p.dimensions, p.elementWidth,
                        p.numUnpackedDimensions)
                    : LogicArray.port(name, p.dimensions, p.elementWidth,
                        p.numUnpackedDimensions);
              case LogicNet():
                return LogicNet.port(name, p.width);
              default:
                return Logic.port(name, p.width);
            }
          })
          .toList(growable: false);

  /// Creates a new instance of a [PairInterface] with the same ports and other
  /// characteristics.
  PairInterface.clone(PairInterface otherInterface)
      : this(
          portsFromConsumer:
              _getMatchPorts(otherInterface, PairDirection.fromConsumer),
          portsFromProvider:
              _getMatchPorts(otherInterface, PairDirection.fromProvider),
          sharedInputPorts:
              _getMatchPorts(otherInterface, PairDirection.sharedInputs),
          commonInOutPorts:
              _getMatchPorts(otherInterface, PairDirection.commonInOuts),
          modify: otherInterface.modify,
        );

  /// A simplified version of [connectIO] for [PairInterface]s where by only
  /// specifying the [role], the input and output tags can be inferred.
  void pairConnectIO(
      Module module, Interface<PairDirection> srcInterface, PairRole role,
      {String Function(String original)? uniquify}) {
    final List<PairDirection> inputTags;
    final List<PairDirection> outputTags;
    final inOutTags = [
      PairDirection.commonInOuts,
    ];

    switch (role) {
      case PairRole.consumer:
        inputTags = [
          PairDirection.sharedInputs,
          PairDirection.fromProvider,
        ];
        outputTags = [
          PairDirection.fromConsumer,
        ];

      case PairRole.provider:
        inputTags = [
          PairDirection.sharedInputs,
          PairDirection.fromConsumer,
        ];
        outputTags = [
          PairDirection.fromProvider,
        ];
    }

    connectIO(
      module,
      srcInterface,
      inputTags: inputTags,
      outputTags: outputTags,
      inOutTags: inOutTags,
      uniquify: uniquify,
    );
  }

  /// Calls [Interface.connectIO] for ports of this interface as well as
  /// hierarchically for all [subInterfaces].
  @override
  void connectIO(Module module, Interface<dynamic> srcInterface,
      {Iterable<PairDirection>? inputTags,
      Iterable<PairDirection>? outputTags,
      Iterable<PairDirection>? inOutTags,
      String Function(String original)? uniquify}) {
    final nonNullUniquify = uniquify ?? (original) => original;
    final nonNullModify = modify ?? (original) => original;
    String newUniquify(String original) =>
        nonNullUniquify(nonNullModify(original));

    super.connectIO(module, srcInterface,
        inputTags: inputTags,
        outputTags: outputTags,
        inOutTags: inOutTags,
        uniquify: newUniquify);

    if (subInterfaces.isNotEmpty) {
      if (srcInterface is! PairInterface) {
        throw InterfaceTypeException(
            srcInterface,
            'an Interface with subInterfaces'
            ' can only connect to a PairInterface');
      }

      for (final subInterfaceEntry in _subInterfaces.entries) {
        final subInterface = subInterfaceEntry.value.interface;
        final subInterfaceName = subInterfaceEntry.key;

        if (!srcInterface._subInterfaces.containsKey(subInterfaceName)) {
          throw InterfaceTypeException(
              srcInterface, 'missing a sub-interface named $subInterfaceName');
        }

        // handle possible reversal as best as we can
        Iterable<PairDirection>? subIntfInputTags;
        Iterable<PairDirection>? subIntfOutputTags;
        final subIntfInOutTags = inOutTags;

        if (subInterfaceEntry.value.reverse) {
          // swap consumer tag
          if (inputTags?.contains(PairDirection.fromConsumer) ?? false) {
            subIntfOutputTags = [PairDirection.fromConsumer];
          }
          if (outputTags?.contains(PairDirection.fromConsumer) ?? false) {
            subIntfInputTags = [PairDirection.fromConsumer];
          }

          // swap provider tag
          if (outputTags?.contains(PairDirection.fromProvider) ?? false) {
            subIntfInputTags = [PairDirection.fromProvider];
          }
          if (inputTags?.contains(PairDirection.fromProvider) ?? false) {
            subIntfOutputTags = [PairDirection.fromProvider];
          }

          // keep sharedInputs, if it's there
          if (inputTags?.contains(PairDirection.sharedInputs) ?? false) {
            subIntfInputTags = [
              if (subIntfInputTags != null) ...subIntfInputTags,
              PairDirection.sharedInputs,
            ];
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
          inOutTags: subIntfInOutTags,
          uniquify: newUniquify,
        );
      }
    }
  }

  /// A mapping from sub-interface names to instances of sub-interfaces.
  Map<String, PairInterface> get subInterfaces =>
      UnmodifiableMapView(_subInterfaces
          .map((name, subInterface) => MapEntry(name, subInterface.interface)));

  final Map<String, _SubPairInterface> _subInterfaces = {};

  /// Registers a new [subInterface] on this [PairInterface], enabling a simple
  /// way to build hierarchical interface definitions.
  ///
  /// If [reverse] is set, then this [subInterface] will be connected in the
  /// opposite way as it usually is with respect to the [PairRole] specified.
  ///
  /// Sub-interfaces are connected via [connectIO] based on the [name].
  @protected
  PairInterfaceType addSubInterface<PairInterfaceType extends PairInterface>(
    String name,
    PairInterfaceType subInterface, {
    bool reverse = false,
  }) {
    if (_subInterfaces.containsKey(name)) {
      throw InterfaceNameException(
          name,
          'Sub-interface name is not unique.'
          ' There is already a sub-interface with that name');
    }

    if (!Sanitizer.isSanitary(name)) {
      throw InterfaceNameException(name, 'Sub-interface name is not sanitary.');
    }

    _subInterfaces[name] = _SubPairInterface(subInterface, reverse: reverse);
    return subInterface;
  }
}

/// An internal tracking object for sub-interfaces and characteristics useful
/// when connecting it.
class _SubPairInterface<PairInterfaceType extends PairInterface> {
  /// The [interface] for this instance.
  final PairInterfaceType interface;

  /// Whether or not this interface should be connected in a reverse way.
  final bool reverse;

  /// Constructs a new sub-interface tracking object with characteristics.
  _SubPairInterface(this.interface, {required this.reverse});
}
