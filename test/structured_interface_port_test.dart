// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// structured_interface_port_test.dart
// Tests experimental structured interface port registration.
//
// 2026 October 23
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

enum _Direction { toModule, fromModule }

class _ControlInterface extends Interface<_Direction> {
  Logic get request => port('request');
  Logic get enable => port('enable');
  Logic get response => port('response');
  Logic get ready => port('ready');

  _ControlInterface() {
    setPorts(
      [
        Logic.port('request', 2),
        Logic.port('enable'),
      ],
      [_Direction.toModule],
    );
    setPorts(
      [
        Logic.port('response', 2),
        Logic.port('ready'),
      ],
      [_Direction.fromModule],
    );
  }

  @override
  _ControlInterface clone() => _ControlInterface();
}

class _StructuredControlChild extends Module {
  late final _ControlInterface control;

  _StructuredControlChild(_ControlInterface source) {
    control = addStructuredInterface(
      source,
      name: 'control',
      inputTags: {_Direction.toModule},
      outputTags: {_Direction.fromModule},
    );
    control.response <= ~control.request;
    control.ready <= control.enable;
  }
}

class _StructuredControlHarness extends Module {
  late final _ControlInterface control;
  late final _StructuredControlChild child;

  _StructuredControlHarness(Logic request, Logic enable) {
    request = addInput('request', request, width: request.width);
    enable = addInput('enable', enable);
    control = _ControlInterface();
    control.request <= request;
    control.enable <= enable;
    child = _StructuredControlChild(control);
    addOutput('response', width: control.response.width) <= control.response;
    addOutput('ready') <= control.ready;
  }
}

enum _SingleDirection { toModule, fromModule }

class _SingleFieldInterface extends Interface<_SingleDirection> {
  Logic get request => port('request');
  Logic get response => port('response');

  _SingleFieldInterface() {
    setPorts([Logic.port('request', 2)], [_SingleDirection.toModule]);
    setPorts([Logic.port('response', 2)], [_SingleDirection.fromModule]);
  }

  @override
  _SingleFieldInterface clone() => _SingleFieldInterface();
}

class _SingleFieldModule extends Module {
  late final _SingleFieldInterface single;

  _SingleFieldModule(
    _SingleFieldInterface source, {
    String? name,
    String Function(String original)? uniquify,
  }) {
    single = addStructuredInterface(
      source,
      name: name,
      inputTags: {_SingleDirection.toModule},
      outputTags: {_SingleDirection.fromModule},
      uniquify: uniquify,
    );
    single.response <= ~single.request;
  }
}

class _LeafPair extends PairInterface {
  Logic get request => port('request');
  Logic get enable => port('enable');
  Logic get response => port('response');
  Logic get ready => port('ready');
  LogicNet get io => port('io') as LogicNet;

  _LeafPair()
      : super(
          portsFromProvider: [
            Logic.port('request', 2),
            Logic.port('enable'),
          ],
          portsFromConsumer: [
            Logic.port('response', 2),
            Logic.port('ready'),
          ],
          commonInOutPorts: [LogicNet.port('io')],
        );

  @override
  _LeafPair clone() => _LeafPair();
}

class _NestedPair extends PairInterface {
  Logic get rootRequest => port('rootRequest');
  Logic get rootResponse => port('rootResponse');
  _LeafPair get leaf => subInterfaces['leaf']! as _LeafPair;

  _NestedPair()
      : super(
          portsFromProvider: [Logic.port('rootRequest')],
          portsFromConsumer: [Logic.port('rootResponse')],
        ) {
    addSubInterface('leaf', _LeafPair());
  }

  @override
  _NestedPair clone() => _NestedPair();
}

class _StructuredPairConsumer extends Module {
  late final _NestedPair link;

  _StructuredPairConsumer(_NestedPair source) {
    link = addStructuredPairInterface(
      source,
      PairRole.consumer,
      name: 'link',
    );
    link.rootResponse <= link.rootRequest;
    link.leaf.response <= link.leaf.request;
    link.leaf.ready <= link.leaf.enable;
  }
}

void main() {
  tearDown(Simulator.reset);

  test('groups multi-field directions and records the binding', () async {
    final harness = _StructuredControlHarness(Logic(width: 2), Logic());
    await harness.build();

    final child = harness.child;
    expect(child.inputs.keys, equals(['control_in']));
    expect(child.outputs.keys, equals(['control_out']));
    expect(child.input('control_in'), isA<LogicStructure>());
    expect(child.output('control_out'), isA<LogicStructure>());

    final binding = child.structuredInterfacePortBindings.single;
    expect(binding.sourceInterface, same(harness.control));
    expect(binding.internalInterface, same(child.control));
    expect(binding.inputPort, same(child.input('control_in')));
    expect(binding.outputPort, same(child.output('control_out')));
    expect(binding.inputPort!.elements, hasLength(2));
    expect(binding.outputPort!.elements, hasLength(2));
    expect(
      () => child.structuredInterfacePortBindings.add(binding),
      throwsUnsupportedError,
    );

    final sv = harness.dumpSystemVerilog();
    expect(sv, contains('control_in'));
    expect(sv, contains('control_out'));
    expect(sv, isNot(contains('input logic [1:0] control_request')));
    expect(sv, isNot(contains('output logic [1:0] control_response')));

    final vectors = [
      Vector(
        {'request': 0, 'enable': 0},
        {'response': 3, 'ready': 0},
      ),
      Vector(
        {'request': 1, 'enable': 1},
        {'response': 2, 'ready': 1},
      ),
      Vector(
        {'request': 2, 'enable': 0},
        {'response': 1, 'ready': 0},
      ),
    ];
    await SimCompare.checkFunctionalVector(harness, vectors);
    SimCompare.checkIverilogVector(harness, vectors);
  });

  test('uses direct prefixed ports for singleton directions', () async {
    final source = _SingleFieldInterface();
    final module = _SingleFieldModule(source, name: 'single');
    await module.build();

    expect(module.inputs.keys, equals(['single_request']));
    expect(module.outputs.keys, equals(['single_response']));
    expect(module.tryInput('single_in'), isNull);
    expect(module.tryOutput('single_out'), isNull);

    final binding = module.structuredInterfacePortBindings.single;
    expect(binding.inputPort, same(module.input('single_request')));
    expect(binding.outputPort, same(module.output('single_response')));
    expect(binding.inputPort, isNot(isA<LogicStructure>()));
    expect(binding.outputPort, isNot(isA<LogicStructure>()));

    source.request.put(1);
    expect(source.response.value.toInt(), equals(2));
  });

  test('derives singleton prefixes from uniquify', () async {
    final module = _SingleFieldModule(
      _SingleFieldInterface(),
      uniquify: (original) => 'channel_$original',
    );
    await module.build();

    expect(module.inputs.keys, equals(['channel_request']));
    expect(module.outputs.keys, equals(['channel_response']));
  });

  test('preserves pair hierarchy and records subinterface bindings', () async {
    final source = _NestedPair();
    final module = _StructuredPairConsumer(source);
    await module.build();

    expect(module.inputs.keys, contains('link_rootRequest'));
    expect(module.outputs.keys, contains('link_rootResponse'));
    expect(module.inputs.keys, contains('link_leaf_in'));
    expect(module.outputs.keys, contains('link_leaf_out'));
    expect(module.inOuts.keys, contains('io'));

    expect(module.structuredInterfacePortBindings, hasLength(2));
    final rootBinding = module.structuredInterfacePortBindings.singleWhere(
      (binding) => identical(binding.sourceInterface, source),
    );
    final leafBinding = module.structuredInterfacePortBindings.singleWhere(
      (binding) => identical(binding.sourceInterface, source.leaf),
    );
    expect(rootBinding.inputPort, isNot(isA<LogicStructure>()));
    expect(rootBinding.outputPort, isNot(isA<LogicStructure>()));
    expect(leafBinding.inputPort, isA<LogicStructure>());
    expect(leafBinding.outputPort, isA<LogicStructure>());

    final sv = module.dumpSystemVerilog();
    expect(sv, contains('link_leaf_in'));
    expect(sv, contains('link_leaf_out'));
  });
}
