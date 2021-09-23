/// Copyright (C) 2021 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
/// 
/// interface.dart
/// Definitions for interfaces and ports
/// 
/// 2021 May 25
/// Author: Max Korbel <max.korbel@intel.com>
/// 

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';

/// An extension of [Logic] useful for [Interface] definitions.
class Port extends Logic {
  Port(String name, [int width=1]) : super(name: name, width: width);
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

  final Map<String, Logic> _ports = {};
  final Map<String, Set<TagType>> _portToTagMap = {};

  Logic port(String name) => _ports[name]!;
  
  /// Connects [module]'s inputs and outputs up to [srcInterface] and this [Interface].
  /// 
  /// The [srcInterface] should be a new instance of the [Interface] to be used by [module] for
  /// all input and output connectivity.  All signals in the interface with specified [TagType]
  /// will be connected to the [Module] via [Module.addInput] or [Module.addOutput] based on
  /// [inputTags] and [outputTags], respectively.  [append] can be used to uniquifiy port names
  /// by appending a [String] to the end.
  void connectIO(Module module, Interface srcInterface, {Set<TagType>? inputTags, Set<TagType>? outputTags, String append=''}) {
    getPorts(inputTags).forEach((port) {
      setPort(
        // ignore: invalid_use_of_protected_member
        module.addInput(port.name+append, srcInterface.port(port.name), width: port.width),
        portName: port.name
      );
    });
    getPorts(outputTags).forEach((port) {
      // ignore: invalid_use_of_protected_member
      var output = module.addOutput(port.name+append, width: port.width);
      port <= output;
      srcInterface.port(port.name) <= port;
      setPort(
        output,
        portName: port.name
      );
    });
  }


  /// Returns all interface ports associated with the provided [tags].
  List<Logic> getPorts([Set<TagType>? tags]) {
    if(tags == null) {
      return List.from(_ports.values);
    } else {
      var matchingPorts = <Logic>{};
      for(var tag in tags) {
        matchingPorts.addAll(
          _ports.values.where((port) => _portToTagMap[port.name]?.contains(tag) ?? false)
        );
      }
      return matchingPorts.toList();
    }
  }

  /// Adds a single new port to this [Interface], associated with [tags] and with name [portName].
  @protected
  void setPort(Logic port, {List<TagType>? tags, String? portName}) {
    _ports[portName ?? port.name] = port;
    if(tags != null) {
      if(!_portToTagMap.containsKey(port.name)) {
        _portToTagMap[port.name] = <TagType>{};
      }
      _portToTagMap[port.name]!.addAll(tags);
    }
  }

  /// Adds a collection of ports to this [Interface], each associated with all of [tags].
  @protected
  void setPorts(List<Logic> ports,  [List<TagType>? tags]) {
    for (var port in ports) { setPort(port, tags: tags); }
  }
  
}