// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause

import 'package:rohd/rohd.dart';
import 'package:rohd/src/interfaces/interface_structure.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

enum _Direction { input, output }

enum _Registration { unified, retyped, legacy }

class _PayloadInterface extends Interface<_Direction> {
  _PayloadInterface() {
    setPorts([Logic.port('payload', 4)], [_Direction.input]);
    setPorts([Logic.port('result', 4)], [_Direction.output]);
  }

  @override
  _PayloadInterface clone() => _PayloadInterface();
}

class _RetypedPayloadInterface extends _PayloadInterface {
  @override
  _RetypedPayloadInterface clone() => _RetypedPayloadInterface();
}

class _PayloadChild extends Module {
  _PayloadChild(
    _PayloadInterface source, {
    required bool asStruct,
    required _Registration registration,
  }) {
    const inputTags = [_Direction.input];
    const outputTags = [_Direction.output];
    String uniquify(String name) => 'wire_$name';

    final target = _RetypedPayloadInterface();
    final internal = switch (registration) {
      _Registration.unified => addInterface(
          source,
          inputTags: inputTags,
          outputTags: outputTags,
          uniquify: uniquify,
          name: 'link',
          definitionName: 'PayloadView',
          asStruct: asStruct,
        ),
      _Registration.retyped => addInterfaceFrom(
          target,
          source,
          inputTags: inputTags,
          outputTags: outputTags,
          uniquify: uniquify,
          name: 'link',
          definitionName: 'PayloadView',
          asStruct: asStruct,
        ),
      _Registration.legacy => addInterfacePorts(
          source,
          inputTags: inputTags,
          outputTags: outputTags,
          uniquify: uniquify,
          name: 'link',
          definitionName: 'PayloadView',
          asStruct: asStruct,
        ),
    };

    internal.port('result') <= ~internal.port('payload');
  }
}

class _PayloadHarness extends Module {
  late final _PayloadChild child;

  _PayloadHarness({
    required bool asStruct,
    required _Registration registration,
  }) {
    final payload = addInput('payload', Logic(width: 4), width: 4);
    final link = _PayloadInterface();
    link.port('payload') <= payload;
    child = _PayloadChild(
      link,
      asStruct: asStruct,
      registration: registration,
    );
    addOutput('result', width: 4) <= link.port('result');
  }
}

class _Channel extends PairInterface {
  Logic get request => port('request');
  Logic get response => port('response');

  _Channel()
      : super(
          portsFromProvider: [Logic.port('request', 3)],
          portsFromConsumer: [Logic.port('response', 3)],
        );

  @override
  _Channel clone() => _Channel();
}

class _NestedChannel extends PairInterface {
  late final _Channel channel;

  _NestedChannel() {
    channel = addSubInterface('channel', _Channel());
  }

  @override
  _NestedChannel clone() => _NestedChannel();
}

class _RetypedNestedChannel extends _NestedChannel {
  @override
  _RetypedNestedChannel clone() => _RetypedNestedChannel();
}

class _ChannelChild extends Module {
  _ChannelChild(
    _NestedChannel source, {
    required bool asStruct,
    required _Registration registration,
  }) {
    String uniquify(String name) => 'wire_$name';
    final target = _RetypedNestedChannel();
    final internal = switch (registration) {
      _Registration.unified => addPairInterface(
          source,
          PairRole.consumer,
          uniquify: uniquify,
          name: 'main',
          definitionName: 'RequestResponse',
          asStruct: asStruct,
        ),
      _Registration.retyped => addPairInterfaceFrom(
          target,
          source,
          PairRole.consumer,
          uniquify: uniquify,
          name: 'main',
          definitionName: 'RequestResponse',
          asStruct: asStruct,
        ),
      _Registration.legacy => addPairInterfacePorts(
          source,
          PairRole.consumer,
          uniquify: uniquify,
          name: 'main',
          definitionName: 'RequestResponse',
          asStruct: asStruct,
        ),
    };

    internal.channel.response <= ~internal.channel.request;
  }
}

class _ChannelHarness extends Module {
  late final _ChannelChild child;

  _ChannelHarness({
    required bool asStruct,
    required _Registration registration,
  }) {
    final request = addInput('request', Logic(width: 3), width: 3);
    final link = _NestedChannel();
    link.channel.request <= request;
    child = _ChannelChild(
      link,
      asStruct: asStruct,
      registration: registration,
    );
    addOutput('response', width: 3) <= link.channel.response;
  }
}

class _DefaultRegistration extends Module {
  _DefaultRegistration() {
    final generic = addInterface(
      _PayloadInterface(),
      inputTags: [_Direction.input],
      outputTags: [_Direction.output],
      name: 'generic',
    );
    generic.port('result') <= generic.port('payload');

    final genericLegacy = addInterfacePorts(
      _PayloadInterface(),
      inputTags: [_Direction.input],
      outputTags: [_Direction.output],
      uniquify: (name) => 'genericLegacy_$name',
    );
    genericLegacy.port('result') <= genericLegacy.port('payload');

    final pair = addPairInterface(
      _Channel(),
      PairRole.consumer,
      name: 'pair',
    );
    pair.response <= pair.request;

    final pairLegacy = addPairInterfacePorts(
      _Channel(),
      PairRole.consumer,
      uniquify: (name) => 'pairLegacy_$name',
    );
    pairLegacy.response <= pairLegacy.request;
  }
}

void main() {
  tearDown(Simulator.reset);

  test('unified APIs group ports by default while legacy APIs stay flat',
      () async {
    final module = _DefaultRegistration();
    await module.build();

    expect(module.inputs['generic_in'], isA<LogicStructure>());
    expect(module.outputs['generic_out'], isA<LogicStructure>());
    expect(module.inputs['pair_in'], isA<LogicStructure>());
    expect(module.outputs['pair_out'], isA<LogicStructure>());
    expect(
      module.inputs['genericLegacy_payload'],
      isNot(isA<LogicStructure>()),
    );
    expect(
      module.outputs['genericLegacy_result'],
      isNot(isA<LogicStructure>()),
    );
    expect(module.inputs['pairLegacy_request'], isNot(isA<LogicStructure>()));
    expect(module.outputs['pairLegacy_response'], isNot(isA<LogicStructure>()));
  });

  for (final registration in _Registration.values) {
    for (final asStruct in [false, true]) {
      test('$registration generic registration asStruct=$asStruct', () async {
        final module = _PayloadHarness(
          asStruct: asStruct,
          registration: registration,
        );
        await module.build();

        if (asStruct) {
          final input = module.child.inputs['link_in'];
          final output = module.child.outputs['link_out'];
          expect(input, isA<InterfaceStructure>());
          expect(output, isA<InterfaceStructure>());
          expect(
            (input! as InterfaceStructure).interfaceTypeName,
            'PayloadView_in',
          );
          expect(
            (output! as InterfaceStructure).interfaceTypeName,
            'PayloadView_out',
          );
        } else {
          expect(module.child.inputs['wire_payload'], isNotNull);
          expect(module.child.outputs['wire_result'], isNotNull);
        }

        final vectors = [
          for (var payload = 0; payload < 16; payload++)
            Vector({'payload': payload}, {'result': payload ^ 15}),
        ];
        await SimCompare.checkFunctionalVector(module, vectors);
        SimCompare.checkIverilogVector(module, vectors);
      });
    }
  }

  for (final registration in _Registration.values) {
    for (final asStruct in [false, true]) {
      test('$registration pair registration asStruct=$asStruct', () async {
        final module = _ChannelHarness(
          asStruct: asStruct,
          registration: registration,
        );
        await module.build();

        if (asStruct) {
          final input = module.child.inputs['main_in'];
          final output = module.child.outputs['main_out'];
          expect(input, isA<InterfaceStructure>());
          expect(output, isA<InterfaceStructure>());
          expect(
            (input! as InterfaceStructure).interfaceTypeName,
            'RequestResponse_in',
          );
          expect(
            (output! as InterfaceStructure).interfaceTypeName,
            'RequestResponse_out',
          );
        } else {
          expect(
            module.child.inputs.values.single,
            isNot(isA<LogicStructure>()),
          );
          expect(
            module.child.outputs.values.single,
            isNot(isA<LogicStructure>()),
          );
        }

        final vectors = [
          for (var request = 0; request < 8; request++)
            Vector({'request': request}, {'response': request ^ 7}),
        ];
        await SimCompare.checkFunctionalVector(module, vectors);
        SimCompare.checkIverilogVector(module, vectors);
      });
    }
  }
}
