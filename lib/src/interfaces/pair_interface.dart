// Copyright (C) 2023-2025 Intel Corporation
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
import 'package:rohd/src/interfaces/interface_structure.dart';
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
  @Deprecated(
      'Use `uniquify` when connecting or adding sub interfaces instead.')
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
    @Deprecated(
        'Use `uniquify` when connecting or adding sub interfaces instead.')
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
  @Deprecated('Use `clone()` on an instance instead')
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
      String Function(String original)? uniquify,
      String? groupName}) {
    final nonNullUniquify = uniquify ?? (original) => original;
    // ignore: deprecated_member_use_from_same_package
    final nonNullModify = modify ?? (original) => original;
    String newUniquify(String original) =>
        nonNullUniquify(nonNullModify(original));

    super.connectIO(module, srcInterface,
        inputTags: inputTags,
        outputTags: outputTags,
        inOutTags: inOutTags,
        uniquify: newUniquify,
        groupName: groupName);

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

        final nonNullSubIntfUniquify =
            subInterfaceEntry.value.uniquify ?? (original) => original;

        String newSubIntfUniquify(String original) =>
            nonNullUniquify(nonNullSubIntfUniquify(nonNullModify(original)));

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
          uniquify: newSubIntfUniquify,
          groupName: subInterfaceName,
        );
      }
    }
  }

  /// Like [pairConnectIO], but groups ports by direction into
  /// [LogicStructure] ports for struct-typed SV generation.
  void pairConnectIOAsStruct(
      Module module, Interface<PairDirection> srcInterface, PairRole role,
      {String Function(String original)? uniquify, String? structName}) {
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

    connectIOAsStruct(
      module,
      srcInterface,
      inputTags: inputTags,
      outputTags: outputTags,
      inOutTags: inOutTags,
      uniquify: uniquify,
      structName: structName,
    );
  }

  /// Builds hierarchical [InterfaceStructure] ports that mirror the
  /// sub-interface hierarchy, grouping all input-tagged ports into a single
  /// `_in` struct and all output-tagged ports into a single `_out` struct.
  void connectIOAsStruct(
    Module module,
    Interface<dynamic> srcInterface, {
    Iterable<PairDirection>? inputTags,
    Iterable<PairDirection>? outputTags,
    Iterable<PairDirection>? inOutTags,
    String Function(String original)? uniquify,
    String? structName,
  }) {
    final nonNullUniquify = uniquify ?? (original) => original;
    // ignore: deprecated_member_use_from_same_package
    final nonNullModify = modify ?? (original) => original;
    String newUniquify(String original) =>
        nonNullUniquify(nonNullModify(original));

    if (srcInterface is! PairInterface) {
      throw InterfaceTypeException(
          srcInterface, 'connectIOAsStruct requires a PairInterface source');
    }

    final intfTypeName = structName ?? _deriveInterfaceTypeName(srcInterface);

    // Build hierarchical input + output structs from entire sub-interface tree
    final inputMappings = <_PortMapping>[];
    final outputMappings = <_PortMapping>[];
    final result = _buildHierarchicalStructPair(
      srcInterface: srcInterface,
      inputTags: inputTags ?? const [],
      outputTags: outputTags ?? const [],
      structName: intfTypeName,
      inputMappings: inputMappings,
      outputMappings: outputMappings,
    );

    // Wire hierarchical input struct
    if (result.inputStruct != null) {
      final srcStruct = result.inputStruct!;

      // Drive fresh struct leaf elements from srcInterface ports
      for (var i = 0; i < inputMappings.length; i++) {
        final m = inputMappings[i];
        srcStruct.leafElements[i] <= m.srcIntf.port(m.portName);
      }

      // Register as a single typed input on the module
      final modulePort = module.addTypedInput(
        newUniquify(srcStruct.name),
        srcStruct,
      );

      // Wire this interface hierarchy's ports from the module port
      for (var i = 0; i < inputMappings.length; i++) {
        final m = inputMappings[i];
        m.thisIntf.port(m.portName) <= modulePort.leafElements[i];
      }
    }

    // Wire hierarchical output struct
    if (result.outputStruct != null) {
      final outTemplate = result.outputStruct!;

      // Register as a single typed output on the module
      final modulePort = module.addTypedOutput(
        newUniquify(outTemplate.name),
        ({name = ''}) => outTemplate.clone(
          name: name.isEmpty ? outTemplate.name : name,
        ),
      );

      // Drive output struct elements from this interface's ports
      for (var i = 0; i < outputMappings.length; i++) {
        final m = outputMappings[i];
        modulePort.leafElements[i] <= m.thisIntf.port(m.portName);
      }

      // Wire srcInterface ports from output struct elements
      for (var i = 0; i < outputMappings.length; i++) {
        final m = outputMappings[i];
        m.srcIntf.port(m.portName) <= modulePort.leafElements[i];
      }
    }

    // InOut ports are still connected individually (can't be in packed structs)
    if (inOutTags != null) {
      _connectInOutsHierarchically(
          module, srcInterface, inOutTags, newUniquify);
    }
  }

  /// Recursively builds hierarchical [InterfaceStructure]s for input and
  /// output directions, mirroring the sub-interface hierarchy.
  ({InterfaceStructure? inputStruct, InterfaceStructure? outputStruct})
      _buildHierarchicalStructPair({
    required PairInterface srcInterface,
    required Iterable<PairDirection> inputTags,
    required Iterable<PairDirection> outputTags,
    required String structName,
    required List<_PortMapping> inputMappings,
    required List<_PortMapping> outputMappings,
  }) {
    final inputElements = <Logic>[];
    final outputElements = <Logic>[];

    // 1. Collect direct ports at this level
    if (inputTags.isNotEmpty) {
      for (final entry in getPorts(inputTags.toSet()).entries) {
        final srcPort = srcInterface.port(entry.key);
        inputElements.add(Logic(name: srcPort.name, width: srcPort.width));
        inputMappings.add(_PortMapping(this, srcInterface, entry.key));
      }
    }

    if (outputTags.isNotEmpty) {
      for (final entry in getPorts(outputTags.toSet()).entries) {
        final p = port(entry.key);
        outputElements.add(Logic(name: p.name, width: p.width));
        outputMappings.add(_PortMapping(this, srcInterface, entry.key));
      }
    }

    // 2. Recurse into sub-interfaces
    for (final subEntry in _subInterfaces.entries) {
      final subName = subEntry.key;
      final subIntf = subEntry.value.interface;

      if (!srcInterface._subInterfaces.containsKey(subName)) {
        throw InterfaceTypeException(
            srcInterface, 'missing a sub-interface named $subName');
      }
      final srcSubIntf = srcInterface._subInterfaces[subName]!.interface;

      // Compute tags for sub-interface (handle reversal)
      final subTags =
          _computeSubTags(inputTags, outputTags, subEntry.value.reverse);

      final subResult = subIntf._buildHierarchicalStructPair(
        srcInterface: srcSubIntf,
        inputTags: subTags.inputTags,
        outputTags: subTags.outputTags,
        structName: subName,
        inputMappings: inputMappings,
        outputMappings: outputMappings,
      );

      if (subResult.inputStruct != null) {
        inputElements.add(subResult.inputStruct!);
      }
      if (subResult.outputStruct != null) {
        outputElements.add(subResult.outputStruct!);
      }
    }

    // 3. Build structs (null if no matching ports at any depth)
    final intfTypeName = _deriveInterfaceTypeName(srcInterface);

    return (
      inputStruct: inputElements.isEmpty
          ? null
          : InterfaceStructure(
              inputElements,
              interfaceTypeName: '${intfTypeName}_in',
              name: '${structName}_in',
            ),
      outputStruct: outputElements.isEmpty
          ? null
          : InterfaceStructure(
              outputElements,
              interfaceTypeName: '${intfTypeName}_out',
              name: '${structName}_out',
            ),
    );
  }

  /// Computes sub-interface input/output tags, applying direction reversal
  /// when the sub-interface is marked as [reverse].
  static ({List<PairDirection> inputTags, List<PairDirection> outputTags})
      _computeSubTags(
    Iterable<PairDirection> inputTags,
    Iterable<PairDirection> outputTags,
    bool reverse,
  ) {
    if (!reverse) {
      return (inputTags: inputTags.toList(), outputTags: outputTags.toList());
    }

    final subInputTags = <PairDirection>[];
    final subOutputTags = <PairDirection>[];

    // fromConsumer: swap between input and output
    if (inputTags.contains(PairDirection.fromConsumer)) {
      subOutputTags.add(PairDirection.fromConsumer);
    }
    if (outputTags.contains(PairDirection.fromConsumer)) {
      subInputTags.add(PairDirection.fromConsumer);
    }

    // fromProvider: swap between input and output
    if (outputTags.contains(PairDirection.fromProvider)) {
      subInputTags.add(PairDirection.fromProvider);
    }
    if (inputTags.contains(PairDirection.fromProvider)) {
      subOutputTags.add(PairDirection.fromProvider);
    }

    // sharedInputs: always stays as input
    if (inputTags.contains(PairDirection.sharedInputs)) {
      subInputTags.add(PairDirection.sharedInputs);
    }

    return (inputTags: subInputTags, outputTags: subOutputTags);
  }

  /// Recursively connects inOut ports individually across the sub-interface
  /// hierarchy.
  void _connectInOutsHierarchically(
    Module module,
    PairInterface srcInterface,
    Iterable<PairDirection> inOutTags,
    String Function(String) uniquify,
  ) {
    // Connect this level's inOuts
    for (final p in getPorts(inOutTags.toSet()).values) {
      if (p is LogicArray) {
        if (!p.isNet) {
          throw PortTypeException(
              p, 'LogicArray nets must be used for inOut array ports.');
        }
        p <=
            module.addInOutArray(
              uniquify(p.name),
              srcInterface.port(p.name),
              dimensions: p.dimensions,
              elementWidth: p.elementWidth,
              numUnpackedDimensions: p.numUnpackedDimensions,
            );
      } else if (p is LogicNet) {
        p <=
            module.addInOut(
              uniquify(p.name),
              srcInterface.port(p.name),
              width: p.width,
            );
      } else {
        throw PortTypeException(p, 'LogicNet must be used for inOut ports.');
      }
    }

    // Recurse into sub-interfaces
    for (final subEntry in _subInterfaces.entries) {
      final subName = subEntry.key;
      final subIntf = subEntry.value.interface;

      if (!srcInterface._subInterfaces.containsKey(subName)) {
        throw InterfaceTypeException(
            srcInterface, 'missing a sub-interface named $subName');
      }
      final srcSubIntf = srcInterface._subInterfaces[subName]!.interface;

      final subUniquify =
          subEntry.value.uniquify ?? (String original) => original;
      String subUq(String original) => uniquify(subUniquify(original));

      subIntf._connectInOutsHierarchically(
          module, srcSubIntf, inOutTags, subUq);
    }
  }

  /// Derives an interface type name from the runtime type of the interface.
  static String _deriveInterfaceTypeName(Interface<dynamic> srcInterface) {
    final runtimeName = srcInterface.runtimeType.toString();
    final baseName = runtimeName.contains('<')
        ? runtimeName.substring(0, runtimeName.indexOf('<'))
        : runtimeName;
    if (baseName == 'Interface' || baseName == 'PairInterface') {
      return 'intf';
    }
    return baseName;
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
  ///
  /// The [uniquify] function can be used to rename ports as they are created on
  /// [Module] boundaries during [connectIO].
  @protected
  PairInterfaceType addSubInterface<PairInterfaceType extends PairInterface>(
    String name,
    PairInterfaceType subInterface, {
    bool reverse = false,
    String Function(String original)? uniquify,
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

    _subInterfaces[name] = _SubPairInterface(
      subInterface,
      reverse: reverse,
      uniquify: uniquify,
    );
    return subInterface;
  }

  /// Makes `this` drive interface signals tagged with [tags] on [other].
  ///
  /// In addition to the base [Interface.driveOther] functionality, this also
  /// handles driving signals on all [subInterfaces] hierarchically when [other]
  /// is a [PairInterface], considering `reverse`.
  @override
  void driveOther(
      Interface<PairDirection> other, Iterable<PairDirection> tags) {
    super.driveOther(other, tags);

    if (other is PairInterface) {
      subInterfaces.forEach((subIntfName, subInterface) {
        if (!other.subInterfaces.containsKey(subIntfName)) {
          throw InterfaceTypeException(
              other, 'missing a sub-interface named $subIntfName');
        }

        if (_subInterfaces[subIntfName]!.reverse) {
          subInterface.receiveOther(other.subInterfaces[subIntfName]!, tags);
        } else {
          subInterface.driveOther(other.subInterfaces[subIntfName]!, tags);
        }
      });
    }
  }

  /// Makes `this` signals tagged with [tags] be driven by [other].
  ///
  /// In addition to the base [Interface.receiveOther] functionality, this also
  /// handles receiving signals from all [subInterfaces] hierarchically when
  /// [other] is a [PairInterface], considering `reverse`.
  @override
  void receiveOther(
      Interface<PairDirection> other, Iterable<PairDirection> tags) {
    super.receiveOther(other, tags);

    if (other is PairInterface) {
      subInterfaces.forEach((subIntfName, subInterface) {
        if (!other.subInterfaces.containsKey(subIntfName)) {
          throw InterfaceTypeException(
              other, 'missing a sub-interface named $subIntfName');
        }

        if (_subInterfaces[subIntfName]!.reverse) {
          subInterface.driveOther(other.subInterfaces[subIntfName]!, tags);
        } else {
          subInterface.receiveOther(other.subInterfaces[subIntfName]!, tags);
        }
      });
    }
  }

  /// Makes `this` conditionally drive interface signals tagged with [tags] on
  /// [other].
  ///
  /// In addition to the base [Interface.conditionalDriveOther] functionality,
  /// this also handles conditional driving of signals on all [subInterfaces]
  /// hierarchically when [other] is a [PairInterface]. Returns a
  /// [ConditionalGroup] that combines all conditionals from the main interface
  /// and sub-interfaces, considering `reverse`.
  @override
  Conditional conditionalDriveOther(
      Interface<PairDirection> other, Iterable<PairDirection> tags) {
    final conditionals = <Conditional>[
      super.conditionalDriveOther(other, tags)
    ];

    if (other is PairInterface) {
      subInterfaces.forEach((subIntfName, subInterface) {
        if (!other.subInterfaces.containsKey(subIntfName)) {
          throw InterfaceTypeException(
              other, 'missing a sub-interface named $subIntfName');
        }

        if (_subInterfaces[subIntfName]!.reverse) {
          conditionals.add(subInterface.conditionalReceiveOther(
              other.subInterfaces[subIntfName]!, tags));
        } else {
          conditionals.add(subInterface.conditionalDriveOther(
              other.subInterfaces[subIntfName]!, tags));
        }
      });
    }

    return ConditionalGroup(conditionals);
  }

  /// Makes `this` signals tagged with [tags] be driven conditionally by
  /// [other].
  ///
  /// In addition to the base [Interface.conditionalReceiveOther] functionality,
  /// this also handles conditional receiving of signals from all
  /// [subInterfaces] hierarchically when [other] is a [PairInterface]. Returns
  /// a [ConditionalGroup] that combines all conditionals from the main
  /// interface and sub-interfaces, considering `reverse`.
  @override
  Conditional conditionalReceiveOther(
      Interface<PairDirection> other, Iterable<PairDirection> tags) {
    final conditionals = <Conditional>[
      super.conditionalReceiveOther(other, tags)
    ];

    if (other is PairInterface) {
      subInterfaces.forEach((subIntfName, subInterface) {
        if (!other.subInterfaces.containsKey(subIntfName)) {
          throw InterfaceTypeException(
              other, 'missing a sub-interface named $subIntfName');
        }

        if (_subInterfaces[subIntfName]!.reverse) {
          conditionals.add(subInterface.conditionalDriveOther(
              other.subInterfaces[subIntfName]!, tags));
        } else {
          conditionals.add(subInterface.conditionalReceiveOther(
              other.subInterfaces[subIntfName]!, tags));
        }
      });
    }

    return ConditionalGroup(conditionals);
  }

  @override
  @mustBeOverridden
  // ignore: deprecated_member_use_from_same_package
  PairInterface clone() => PairInterface.clone(this);
}

/// An internal tracking object for sub-interfaces and characteristics useful
/// when connecting it.
class _SubPairInterface<PairInterfaceType extends PairInterface> {
  /// The [interface] for this instance.
  final PairInterfaceType interface;

  /// Whether or not this interface should be connected in a reverse way.
  final bool reverse;

  /// A function to uniquify/rename ports on a per-subInterface basis.
  final String Function(String original)? uniquify;

  /// Constructs a new sub-interface tracking object with characteristics.
  _SubPairInterface(this.interface, {required this.reverse, this.uniquify});
}

/// Tracks a port mapping between the local (this) and source interfaces,
/// used for wiring hierarchical struct ports.
class _PortMapping {
  /// The local interface (inside the module) owning the port.
  final PairInterface thisIntf;

  /// The source interface (outside the module) owning the port.
  final PairInterface srcIntf;

  /// The port name on both interfaces.
  final String portName;

  _PortMapping(this.thisIntf, this.srcIntf, this.portName);
}
