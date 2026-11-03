// Copyright (C) 2021-2026 Intel Corporation
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
import 'package:rohd/src/signals/signals.dart';
import 'package:rohd/src/utilities/sanitizer.dart';

/// Represents a logical interface to a [Module].
///
/// Interfaces make it easier to define port connections of a [Module] in a
/// reusable way.  The [TagType] allows grouping of port signals of the module
/// when connecting at a [Module] level.
///
/// When connecting an [Interface] to a [Module], you should always create a new
/// instance of the [Interface] so you don't modify the one being passed in
/// through the constructor.  Modifying the same [Interface] as was passed would
/// have negative consequences if multiple [Module]s were consuming the same
/// [Interface], and also breaks the rules for [Module] input and output
/// connectivity.
class Interface<TagType extends Enum> {
  /// Internal map from the [Interface]'s defined port name to an instance
  /// of a [Logic].
  ///
  /// Note that each port's name (`port.name`) does not necessarily match the
  /// keys of [_ports] if they have been uniquified.
  final Map<String, Logic> _ports = {};

  /// Maps from the [Interface]'s defined port name to an instance
  /// of a [Logic].
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
      : throw PortDoesNotExistException(
          'Port named "$name" not found on this interface: $this.');

  /// Provides the [port] named [name] if it exists, otherwise `null`.
  Logic? tryPort(String name) => _ports[name];

  /// Connects [module]'s inputs, outputs, and inOuts up to [srcInterface] and
  /// this [Interface].
  ///
  /// The [srcInterface] should be an external instance of the [Interface]
  /// passed in from outside the [module], and [connectIO] should be called on a
  /// new instance of the [Interface] to be used by [module] for all input and
  /// output connectivity.  For example:
  ///
  /// ```dart
  /// MyMod(MyIntf srcIntf) {
  ///   srcIntf = MyIntf(args)..connectIO(this, srcIntf, inputTags: ... );
  /// }
  /// ```
  ///
  /// All signals in the interface with specified [TagType] will be connected
  /// to the [Module] via [Module.addInput], [Module.addOutput], or
  /// [Module.addInOut] based on [inputTags], [outputTags], and [inOutTags],
  /// respectively. [uniquify] can be used to uniquifiy port names by
  /// manipulating the original name of the port.
  ///
  /// If [inputTags], [outputTags], or [inOutTags] is not specified, then,
  /// respectively, no inputs, outputs, or inOuts will be added.
  void connectIO(Module module, Interface<dynamic> srcInterface,
      {Iterable<TagType>? inputTags,
      Iterable<TagType>? outputTags,
      Iterable<TagType>? inOutTags,
      String Function(String original)? uniquify}) {
    uniquify ??= (original) => original;

    if (inputTags != null) {
      for (final port in getPorts(inputTags).values) {
        port <=
            switch (port) {
              LogicArray() => module.addInputArray(
                  uniquify(port.name),
                  srcInterface.port(port.name),
                  dimensions: port.dimensions,
                  elementWidth: port.elementWidth,
                  numUnpackedDimensions: port.numUnpackedDimensions,
                ),
              BaseLogicArray() => module.addTypedInput(
                  uniquify(port.name),
                  srcInterface.port(port.name) as BaseLogicArray,
                ),
              _ => module.addInput(
                  uniquify(port.name),
                  srcInterface.port(port.name),
                  width: port.width,
                ),
            };
      }
    }

    if (outputTags != null) {
      for (final port in getPorts(outputTags).values) {
        final output = switch (port) {
          LogicArray() => module.addOutputArray(
              uniquify(port.name),
              dimensions: port.dimensions,
              elementWidth: port.elementWidth,
              numUnpackedDimensions: port.numUnpackedDimensions,
            ),
          BaseLogicArray() => module.addTypedOutput(
              uniquify(port.name),
              port.clone,
            ),
          _ => module.addOutput(
              uniquify(port.name),
              width: port.width,
            ),
        };
        output <= port;
        srcInterface.port(port.name) <= output;
      }
    }

    if (inOutTags != null) {
      _connectInOutPorts(
        module,
        srcInterface,
        inOutTags,
        uniquify: uniquify,
      );
    }
  }

  /// Connects this local interface through directional grouped ports.
  ///
  /// A direction with two or more selected fields becomes one typed
  /// [LogicStructure] port. A single selected field becomes a direct port
  /// named `<interface>_<field>`. InOut fields remain individual net ports.
  ///
  /// The returned registrations let [Module] retain the relationship between
  /// the external interface, this internal clone, and its directional ports.
  @internal
  List<InterfaceStructuredPortRegistration> connectIOAsStructuredPorts(
    Module module,
    Interface<dynamic> srcInterface, {
    Iterable<TagType>? inputTags,
    Iterable<TagType>? outputTags,
    Iterable<TagType>? inOutTags,
    String Function(String original)? uniquify,
    String? name,
  }) {
    final prefix = _structuredPortPrefix(
      srcInterface,
      name: name,
      uniquify: uniquify,
    );
    Logic? inputPort;
    Logic? outputPort;

    if (inputTags != null) {
      final entries = getPorts(inputTags).entries.toList(growable: false);
      if (entries.length == 1) {
        final entry = entries.single;
        final modulePort = _addSingleInputPort(
          module,
          _structuredFieldName(prefix, entry.key),
          srcInterface.port(entry.key),
        );
        port(entry.key) <= modulePort;
        inputPort = modulePort;
      } else if (entries.length > 1) {
        final sourceStructure = LogicStructure(
          [
            for (final entry in entries)
              srcInterface
                  .port(entry.key)
                  .clone(name: _structuredFieldName(prefix, entry.key)),
          ],
          name: '${prefix}_in',
        );
        for (final (index, entry) in entries.indexed) {
          sourceStructure.elements[index] <= srcInterface.port(entry.key);
        }
        final modulePort = module.addTypedInput<LogicStructure>(
            sourceStructure.name, sourceStructure);
        for (final (index, entry) in entries.indexed) {
          port(entry.key) <= modulePort.elements[index];
        }
        inputPort = modulePort;
      }
    }

    if (outputTags != null) {
      final entries = getPorts(outputTags).entries.toList(growable: false);
      if (entries.length == 1) {
        final entry = entries.single;
        final modulePort = _addSingleOutputPort(
          module,
          _structuredFieldName(prefix, entry.key),
          port(entry.key),
        );
        modulePort <= port(entry.key);
        srcInterface.port(entry.key) <= modulePort;
        outputPort = modulePort;
      } else if (entries.length > 1) {
        final template = LogicStructure(
          [
            for (final entry in entries)
              port(entry.key)
                  .clone(name: _structuredFieldName(prefix, entry.key)),
          ],
          name: '${prefix}_out',
        );
        final modulePort = module.addTypedOutput<LogicStructure>(
          template.name,
          template.clone,
        );
        for (final (index, entry) in entries.indexed) {
          modulePort.elements[index] <= port(entry.key);
          srcInterface.port(entry.key) <= modulePort.elements[index];
        }
        outputPort = modulePort;
      }
    }

    if (inOutTags != null) {
      _connectInOutPorts(
        module,
        srcInterface,
        inOutTags,
        uniquify: uniquify ?? (original) => original,
      );
    }

    return [
      InterfaceStructuredPortRegistration(
        sourceInterface: srcInterface,
        internalInterface: this,
        inputPort: inputPort,
        outputPort: outputPort,
      ),
    ];
  }

  void _connectInOutPorts(
    Module module,
    Interface<dynamic> srcInterface,
    Iterable<TagType> inOutTags, {
    required String Function(String original) uniquify,
  }) {
    for (final port in getPorts(inOutTags).values) {
      if (port is BaseLogicArray) {
        if (!port.isNet) {
          throw PortTypeException(
              port, 'LogicArray nets must be used for inOut array ports.');
        }
      } else if (port is! LogicNet) {
        throw PortTypeException(port, 'LogicNet must be used for inOut ports.');
      }

      port <=
          switch (port) {
            LogicArray() => module.addInOutArray(
                uniquify(port.name),
                srcInterface.port(port.name),
                dimensions: port.dimensions,
                elementWidth: port.elementWidth,
                numUnpackedDimensions: port.numUnpackedDimensions,
              ),
            BaseLogicArray() => module.addTypedInOut(
                uniquify(port.name),
                srcInterface.port(port.name) as BaseLogicArray,
              ),
            _ => module.addInOut(
                uniquify(port.name),
                srcInterface.port(port.name),
                width: port.width,
              ),
          };
    }
  }

  static Logic _addSingleInputPort(
    Module module,
    String name,
    Logic source,
  ) =>
      switch (source) {
        LogicArray() => module.addInputArray(
            name,
            source,
            dimensions: source.dimensions,
            elementWidth: source.elementWidth,
            numUnpackedDimensions: source.numUnpackedDimensions,
          ),
        BaseLogicArray() => module.addTypedInput(name, source),
        LogicStructure() => module.addTypedInput(name, source),
        LogicEnum() => module.addTypedInput(name, source),
        _ => module.addInput(name, source, width: source.width),
      };

  static Logic _addSingleOutputPort(
    Module module,
    String name,
    Logic template,
  ) =>
      switch (template) {
        LogicArray() => module.addOutputArray(
            name,
            dimensions: template.dimensions,
            elementWidth: template.elementWidth,
            numUnpackedDimensions: template.numUnpackedDimensions,
          ),
        BaseLogicArray() => module.addTypedOutput(name, template.clone),
        LogicStructure() => module.addTypedOutput(name, template.clone),
        LogicEnum() => module.addTypedOutput(name, template.clone),
        _ => module.addOutput(name, width: template.width),
      };

  static String _structuredPortPrefix(
    Interface<dynamic> source, {
    required String? name,
    required String Function(String original)? uniquify,
  }) {
    if (name != null) {
      return Sanitizer.sanitizeSV(name);
    }

    if (uniquify != null) {
      const sentinel = '__rohd_interface_prefix__';
      final renamed = uniquify(sentinel);
      final prefix = switch (renamed) {
        final value when value.endsWith(sentinel) =>
          value.substring(0, value.length - sentinel.length),
        final value when value.startsWith(sentinel) =>
          value.substring(sentinel.length),
        _ => '',
      }
          .replaceAll(RegExp(r'^_+|_+$'), '');
      if (prefix.isNotEmpty) {
        return Sanitizer.sanitizeSV(prefix);
      }
    }

    final runtimeName = source.runtimeType.toString();
    final genericStart = runtimeName.indexOf('<');
    final typeName =
        genericStart < 0 ? runtimeName : runtimeName.substring(0, genericStart);
    return Sanitizer.sanitizeSV(
      typeName.replaceAll(RegExp(r'^_+|_+$'), ''),
    );
  }

  static String _structuredFieldName(String prefix, String fieldName) =>
      Sanitizer.sanitizeSV('${prefix}_$fieldName');

  /// Returns all interface ports associated with the provided [tags] as a
  /// [Map] from the port name to the [Logic] port.
  ///
  /// Returns all ports if [tags] is null.
  Map<String, Logic> getPorts([Iterable<TagType>? tags]) {
    if (tags == null) {
      return ports;
    } else {
      final matchingPorts = <String, Logic>{};
      for (final tag in tags.toSet().toList(growable: false)) {
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

    if (_ports.containsKey(portName)) {
      throw DuplicatePortNameException(portName);
    }

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
          .toList(growable: false));

  /// Makes `this` signals tagged with [tags] be driven conditionally by
  /// [other].
  Conditional conditionalReceiveOther(
          Interface<TagType> other, Iterable<TagType> tags) =>
      ConditionalGroup(getPorts(tags)
          .map((portName, thisPort) =>
              MapEntry(portName, thisPort < other.port(portName)))
          .values
          .toList(growable: false));

  /// Creates a new [Interface] with the same ports as `this`.
  ///
  /// It is expected that any implementation will override this in a way that
  /// returns the same type as itself.
  @mustBeOverridden
  Interface<TagType> clone() {
    final newIntf = Interface<TagType>();
    _portToTagMap.forEach((portName, tags) {
      newIntf.setPorts([port(portName).clone()], tags);
    });
    return newIntf;
  }
}

/// Details one directional structured-port registration.
///
/// This internal result lets [Module] expose
/// [StructuredInterfacePortBinding]s without coupling [Interface] to module
/// storage.
@internal
class InterfaceStructuredPortRegistration {
  /// The external interface connected to the module.
  final Interface<dynamic> sourceInterface;

  /// The internal clone used by module logic.
  final Interface<dynamic> internalInterface;

  /// The grouped or singleton input port, if inputs were selected.
  final Logic? inputPort;

  /// The grouped or singleton output port, if outputs were selected.
  final Logic? outputPort;

  /// Creates a structured-port registration.
  const InterfaceStructuredPortRegistration({
    required this.sourceInterface,
    required this.internalInterface,
    required this.inputPort,
    required this.outputPort,
  });
}
