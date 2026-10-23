// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// module_interface_registration_test.dart
// Tests for Module.addStructuredInterface, addInterfaceFrom,
// addStructuredPairInterface, and addPairInterfaceFrom.
//
// 2026 October 21
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

enum _Dir { toModule, fromModule }

class _TagIntf extends Interface<_Dir> {
  Logic get a => port('a');
  Logic get y => port('y');

  _TagIntf() {
    setPorts([Logic.port('a', 4)], [_Dir.toModule]);
    setPorts([Logic.port('y', 4)], [_Dir.fromModule]);
  }

  @override
  _TagIntf clone() => _TagIntf();
}

class _SubPair extends PairInterface {
  _SubPair()
      : super(
          portsFromProvider: [Logic.port('sub_req', 2)],
          portsFromConsumer: [Logic.port('sub_rsp', 2)],
        );

  @override
  _SubPair clone() => _SubPair();
}

class _Pair extends PairInterface {
  Logic get req => port('req');
  Logic get rsp => port('rsp');

  _Pair()
      : super(
          portsFromProvider: [Logic.port('req', 4)],
          portsFromConsumer: [Logic.port('rsp', 4)],
        ) {
    addSubInterface('s', _SubPair(), uniquify: (orig) => 's_$orig');
  }

  @override
  _Pair clone() => _Pair();
}

enum _Api { legacy, add, addFrom }

class _TagModule extends Module {
  late final _TagIntf intf;
  final _TagIntf source;

  _TagModule(this.source, _Api api) : super(definitionName: 'TagModule') {
    intf = switch (api) {
      _Api.legacy => addInterfacePorts(source,
          inputTags: {_Dir.toModule},
          outputTags: {_Dir.fromModule},
          uniquify: (orig) => 'p_$orig'),
      _Api.add => addStructuredInterface(source,
          inputTags: {_Dir.toModule},
          outputTags: {_Dir.fromModule},
          uniquify: (orig) => 'p_$orig'),
      _Api.addFrom => addInterfaceFrom(_TagIntf(), source,
          inputTags: {_Dir.toModule},
          outputTags: {_Dir.fromModule},
          uniquify: (orig) => 'p_$orig'),
    };
    intf.y <= ~intf.a;
  }
}

class _PairModule extends Module {
  late final _Pair intf;
  final _Pair source;

  _PairModule(this.source, _Api api) : super(definitionName: 'PairModule') {
    intf = switch (api) {
      _Api.legacy => addPairInterfacePorts(source, PairRole.consumer,
          uniquify: (orig) => 'c_$orig'),
      _Api.add => addStructuredPairInterface(source, PairRole.consumer,
          uniquify: (orig) => 'c_$orig'),
      _Api.addFrom => addPairInterfaceFrom(_Pair(), source, PairRole.consumer,
          uniquify: (orig) => 'c_$orig'),
    };
    intf.rsp <= intf.req + 1;
    intf.subInterfaces['s']!.port('sub_rsp') <=
        intf.subInterfaces['s']!.port('sub_req');
  }
}

String _body(Module m) {
  final sv = m.dumpSystemVerilog();
  return sv.substring(sv.indexOf('module '));
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('addStructuredInterface', () {
    test('returns a clone with ports matching addInterfacePorts', () async {
      final legacy = _TagModule(_TagIntf(), _Api.legacy);
      await legacy.build();
      final added = _TagModule(_TagIntf(), _Api.add);
      await added.build();

      expect(added.intf, isNot(same(added.source)));
      expect(added.inputs.keys, equals(legacy.inputs.keys));
      expect(added.outputs.keys, equals(legacy.outputs.keys));
      expect(added.inputs.keys, contains('p_a'));
      expect(added.outputs.keys, contains('p_y'));
      expect(_body(added), equals(_body(legacy)));
    });

    test('drives external interface through registered ports', () async {
      final source = _TagIntf();
      final mod = _TagModule(source, _Api.add);
      await mod.build();

      source.a.put(0x3);
      expect(source.y.value.toInt(), equals(0xc),
          reason: 'y should be ~a for a=0x3');
    });
  });

  group('addInterfaceFrom', () {
    test('returns the provided target without cloning', () async {
      final target = _TagIntf();
      late final _TagIntf returned;
      final mod = _TagFromModule(_TagIntf(), target, (r) => returned = r);
      await mod.build();

      expect(returned, same(target));
      expect(mod.inputs.keys, contains('p_a'));
      expect(mod.outputs.keys, contains('p_y'));
    });

    test('matches addStructuredInterface output', () async {
      final added = _TagModule(_TagIntf(), _Api.add);
      await added.build();
      final from = _TagModule(_TagIntf(), _Api.addFrom);
      await from.build();

      expect(_body(from), equals(_body(added)));
    });
  });

  group('addStructuredPairInterface', () {
    test('matches addPairInterfacePorts including sub-interfaces', () async {
      final legacy = _PairModule(_Pair(), _Api.legacy);
      await legacy.build();
      final added = _PairModule(_Pair(), _Api.add);
      await added.build();

      expect(added.intf, isNot(same(added.source)));
      expect(added.inputs.keys, equals(legacy.inputs.keys));
      expect(added.outputs.keys, equals(legacy.outputs.keys));
      expect(added.inputs.keys, containsAll(['c_req', 'c_s_sub_req']));
      expect(added.outputs.keys, containsAll(['c_rsp', 'c_s_sub_rsp']));
      expect(_body(added), equals(_body(legacy)));
    });

    test('drives external pair interface through registered ports', () async {
      final source = _Pair();
      final mod = _PairModule(source, _Api.add);
      await mod.build();

      source.req.put(5);
      source.subInterfaces['s']!.port('sub_req').put(2);
      expect(source.rsp.value.toInt(), equals(6),
          reason: 'rsp should be req + 1 for req=5');
      expect(
          source.subInterfaces['s']!.port('sub_rsp').value.toInt(), equals(2),
          reason: 'sub_rsp should echo sub_req');
    });
  });

  group('addPairInterfaceFrom', () {
    test('returns the provided target and matches addStructuredPairInterface',
        () async {
      final added = _PairModule(_Pair(), _Api.add);
      await added.build();
      final from = _PairModule(_Pair(), _Api.addFrom);
      await from.build();

      expect(from.intf, isNot(same(from.source)));
      expect(_body(from), equals(_body(added)));
    });
  });
}

class _TagFromModule extends Module {
  _TagFromModule(
      _TagIntf source, _TagIntf target, void Function(_TagIntf) onReturn)
      : super(definitionName: 'TagFromModule') {
    final intf = addInterfaceFrom(target, source,
        inputTags: {_Dir.toModule},
        outputTags: {_Dir.fromModule},
        uniquify: (orig) => 'p_$orig');
    onReturn(intf);
    intf.y <= ~intf.a;
  }
}
