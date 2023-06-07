// Copyright (C) 2023 Intel Corporation
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
import 'package:rohd/src/exceptions/interface/interface_exceptions.dart';
import 'package:rohd/src/utilities/sanitizer.dart';

enum PairDirection { fromProvider, fromConsumer, sharedInputs }

enum PairRole { provider, consumer, monitor }

class PairInterface extends Interface<PairDirection> {
  /// A function that can be used to modify all port names in a certain way.
  String Function(String original)? modify;

  //TODO: should modify come as part of the main interface?

  /// TODO(): fix doc
  PairInterface({
    List<Port>? portsFromConsumer,
    List<Port>? portsFromProvider,
    List<Port>? sharedInputPorts,
    this.modify,
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

  PairInterface.clone(PairInterface otherInterface)
      : this(
          portsFromConsumer:
              _getMatchPorts(otherInterface, PairDirection.fromConsumer),
          portsFromProvider:
              _getMatchPorts(otherInterface, PairDirection.fromProvider),
          sharedInputPorts:
              _getMatchPorts(otherInterface, PairDirection.sharedInputs),
          modify: otherInterface.modify,
        );

  void pairConnectIO(
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

      //TODO: test monitor one
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
    final nonNullUniquify = uniquify ?? (original) => original;
    final nonNullModify = modify ?? (original) => original;
    String newUniquify(String original) =>
        nonNullUniquify(nonNullModify(original));

    super.connectIO(module, srcInterface,
        inputTags: inputTags, outputTags: outputTags, uniquify: newUniquify);

    if (subInterfaces.isNotEmpty) {
      if (srcInterface is! PairInterface) {
        throw InterfaceTypeException(
            srcInterface,
            'an Interface with subInterfaces'
            ' can only connect to a PairInterface');
      }

      for (final subInterfaceEntry in _subInterfaces.values) {
        final subInterface = subInterfaceEntry.interface;
        final subInterfaceName = subInterfaceEntry.name;

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
          uniquify: newUniquify,
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
      throw InterfaceNameException(
          name,
          'Sub-interface name is not unique.'
          ' There is already a sub-interface with that name');
    }

    if (!Sanitizer.isSanitary(name)) {
      throw InterfaceNameException(name, 'Sub-interface name is not sanitary.');
    }

    _subInterfaces[name] =
        _SubPairInterface(name, subInterface, reverse: reverse);
    return subInterface;
  }
}

class _SubPairInterface<PairInterfaceType extends PairInterface> {
  final String name;
  final PairInterfaceType interface;
  final bool reverse;
  _SubPairInterface(this.name, this.interface, {required this.reverse});
}
