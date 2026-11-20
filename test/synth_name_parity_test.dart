// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// synth_name_parity_test.dart
// Tests that verify signalNameOfBest works consistently across
// different synthesis paths (SV and netlist).
//
// 2026 April 14
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:convert';

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/utilities/generated_code_references.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

import '../example/filter_bank.dart';

extension _NetlistTestModule on Module {
  String generateNetlist(
      {NetlistSynthesizerConfiguration configuration =
          const NetlistSynthesizerConfiguration(),
      String? packageRoot}) {
    if (!hasBuilt) {
      throw ModuleNotBuiltException(this);
    }

    return NetlistSynthesizer(configuration: configuration)
        .synthesizeToJson(this, packageRoot: packageRoot);
  }
}

class _Counter extends Module {
  _Counter(Logic en, Logic reset, {int width = 8}) : super(name: 'counter') {
    en = addInput('en', en);
    reset = addInput('reset', reset);
    final val = addOutput('val', width: width);
    final nextVal = Logic(name: 'nextVal', width: width);
    nextVal <= val + 1;
    Sequential.multi(
      [SimpleClockGenerator(10).clk, reset],
      [
        If(
          reset,
          then: [val < 0],
          orElse: [
            If(en, then: [val < nextVal]),
          ],
        ),
      ],
    );
  }
}

class _NamingStage extends Module {
  _NamingStage(Logic source,
      {required String inputName, required String outputName}) {
    source = addInput(inputName, source);
    addOutput(outputName) <= ~source;
  }
}

class _DriverReceiverNames extends Module {
  late final Logic driver;
  late final Logic receiver;

  _DriverReceiverNames(
      {String driverName = 'sent', String receiverName = 'received'}) {
    final source = addInput('source', Logic());
    final producer =
        _NamingStage(source, inputName: 'data', outputName: driverName);
    driver = producer.output(driverName);
    final consumer =
        _NamingStage(driver, inputName: receiverName, outputName: 'result');
    receiver = consumer.input(receiverName);
    addOutput('observed') <= consumer.output('result');
  }
}

class _CollidingNames extends Module {
  late final Logic firstDup;
  late final Logic secondDup;

  _CollidingNames(Logic a, Logic b) : super(name: 'collidingNames') {
    a = addInput('a', a);
    b = addInput('b', b);
    final y = addOutput('y');

    firstDup = Logic(name: 'dup');
    secondDup = Logic(name: 'dup');

    firstDup <= a & b;
    secondDup <= a | b;
    y <= firstDup ^ secondDup;
  }
}

class _PartiallyInlineCollidingNames extends Module {
  late final Logic inlinedDup;
  late final Logic retainedDup;

  _PartiallyInlineCollidingNames(Logic a, Logic b)
      : super(name: 'partiallyInlineCollidingNames') {
    a = addInput('a', a);
    b = addInput('b', b);
    final y = addOutput('y');
    final z = addOutput('z');

    inlinedDup = Logic(name: 'dup');
    retainedDup = Logic(name: 'dup');

    inlinedDup <= a & b;
    retainedDup <= a | b;
    y <= inlinedDup ^ retainedDup;
    z <= retainedDup & a;
  }
}

class _CollapsedInstanceCollidingNames extends Module {
  late final Logic retainedDup;

  _CollapsedInstanceCollidingNames(Logic a, Logic b)
      : super(name: 'collapsedInstanceCollidingNames') {
    a = addInput('a', a);
    b = addInput('b', b);
    final y = addOutput('y');
    final z = addOutput('z');

    final collapsedInstanceOut = And2Gate(a, b, name: 'dup').out;
    retainedDup = Logic(name: 'dup');

    retainedDup <= a | b;
    y <= collapsedInstanceOut ^ retainedDup;
    z <= retainedDup;
  }
}

class _NestedNameStructure extends LogicStructure {
  final Logic before;
  final LogicArray lanes;
  final Logic after;

  factory _NestedNameStructure({String? name}) => _NestedNameStructure._(
        Logic(name: 'before', width: 2),
        LogicArray([2], 3, name: 'lanes'),
        Logic(name: 'after'),
        name: name ?? 'nested',
      );

  _NestedNameStructure._(
    this.before,
    this.lanes,
    this.after, {
    required String name,
  }) : super([before, lanes, after], name: name);

  @override
  _NestedNameStructure clone({String? name}) =>
      _NestedNameStructure(name: name ?? this.name);
}

class _NestedNameModule extends Module {
  late final TypedLogicArray<_NestedNameStructure, LogicValue> valuesIn;
  late final TypedLogicArray<_NestedNameStructure, LogicValue> valuesOut;

  _NestedNameModule() : super(name: 'nestedNameModule') {
    final source = TypedLogicArray<_NestedNameStructure, LogicValue>(
      [2],
      _NestedNameStructure.new,
    );
    valuesIn = addTypedInput('valuesIn', source);
    valuesOut = addTypedOutput('valuesOut', valuesIn.clone);
    for (var index = 0; index < 2; index++) {
      valuesOut.at([index]).before <= valuesIn.at([index]).before;
      valuesOut.at([index]).after <= ~valuesIn.at([index]).after;
      for (var lane = 0; lane < 2; lane++) {
        valuesOut.at([index]).lanes.at([lane]) <=
            valuesIn.at([index]).lanes.at([lane]);
      }
    }
  }
}

class _ArrayTraceModule extends Module {
  _ArrayTraceModule() {
    final input = addInputArray('data', LogicArray([4], 8),
        dimensions: [4], elementWidth: 8);
    final index = addInput('index', Logic(width: 2), width: 2);
    final values = LogicArray([4], 8, name: 'values');
    for (var i = 0; i < values.elements.length; i++) {
      values.elements[i] <= input.elements[i];
    }
    addOutput('out', width: 8) <= values.elements.selectIndex(index);
    final distinct =
        Logic(name: 'values_0_', width: 8, naming: Naming.renameable)
          ..gets(input.elements[0] + Const(1, width: 8));
    addOutput('other', width: 8) <= distinct;
    final keyword =
        Logic(name: 'namespace', width: 8, naming: Naming.renameable)
          ..gets(input.elements[1] + Const(2, width: 8));
    addOutput('keyword', width: 8) <= keyword;
  }
}

class _NestedArrayTraceModule extends Module {
  _NestedArrayTraceModule() {
    final array = addInputArray('arr', LogicArray([2, 2], 8),
        dimensions: [2, 2], elementWidth: 8);
    addOutput('out', width: 8) <= ~array.elements[1].elements[0];
  }
}

class _ReverseInternalSignalOrderSynthModuleDefinition
    extends SynthModuleDefinition {
  _ReverseInternalSignalOrderSynthModuleDefinition(super.module);

  @override
  void process() {
    internalSignals
      ..clear()
      ..addAll(internalSignals.toList().reversed);
  }
}

Future<Map<String, String>> _collisionNamesAfter(
  Iterable<void Function(_CollidingNames)> synthesize,
) async {
  final mod = _CollidingNames(Logic(), Logic());
  await mod.build();

  for (final synth in synthesize) {
    synth(mod);
  }

  return {
    'firstDup': mod.namer.signalNameOfBest([mod.firstDup]),
    'secondDup': mod.namer.signalNameOfBest([mod.secondDup]),
  };
}

Future<Map<String, String>> _collisionNamesAfterSynthDefinition(
  SynthModuleDefinition Function(_CollidingNames) createSynthDefinition,
) async {
  final mod = _CollidingNames(Logic(), Logic());
  await mod.build();

  createSynthDefinition(mod);

  return {
    'firstDup': mod.namer.signalNameOfBest([mod.firstDup]),
    'secondDup': mod.namer.signalNameOfBest([mod.secondDup]),
  };
}

Future<Map<String, String>> _partialInlineCollisionNamesAfter(
  Iterable<void Function(_PartiallyInlineCollidingNames)> synthesize,
) async {
  final mod = _PartiallyInlineCollidingNames(Logic(), Logic());
  await mod.build();

  for (final synth in synthesize) {
    synth(mod);
  }

  return {
    'retainedDup': mod.namer.signalNameOfBest([mod.retainedDup]),
    'inlinedDup': mod.namer.signalNameOfBest([mod.inlinedDup]),
  };
}

Future<Map<String, String>> _collapsedInstanceCollisionNamesAfter(
  Iterable<void Function(_CollapsedInstanceCollidingNames)> synthesize,
) async {
  final mod = _CollapsedInstanceCollidingNames(Logic(), Logic());
  await mod.build();

  for (final synth in synthesize) {
    synth(mod);
  }

  return {
    'retainedDup': mod.namer.signalNameOfBest([mod.retainedDup]),
  };
}

class _NameCollisions extends Module {}

void main() {
  test('array helpers leave SystemVerilog names and namespace unchanged',
      () async {
    Future<Module> makeDesign() async {
      final dut = _NameCollisions();
      final input = dut.addInputArray('data', LogicArray([2], 4),
          dimensions: [2], elementWidth: 4);
      final named = (~input.elements[0]).named('array_slice');
      dut.addOutput('out', width: 4).gets(named ^ input.elements[1]);
      await dut.build();
      return dut;
    }

    String generateSv(Module dut) => SystemVerilogService(dut, register: false)
        .output
        .replaceFirst(RegExp(r' \* Generation time: [^\n]*\n'), '');
    final baseline = await makeDesign();
    final expectedSv = generateSv(baseline);
    expect(expectedSv, contains('assign array_slice ='));
    expect(baseline.namer.isAvailable('array_slice_0'), isTrue);

    final dut = await makeDesign();
    final document = jsonDecode(dut.generateNetlist()) as Map<String, dynamic>;
    final definition = (document['modules'] as Map)[dut.definitionName]
        as Map<String, dynamic>;
    expect((definition['netnames'] as Map).keys, contains('array_slice'));
    expect((definition['cells'] as Map).keys, contains('array_slice_0'));
    expect(dut.namer.isAvailable('array_slice_0'), isTrue);
    expect(generateSv(dut), expectedSv);
  });

  test('netlist-only names cannot shadow canonical ports or signals', () async {
    Future<Module> makeDesign() async {
      final dut = _NameCollisions();
      final input = dut.addInput('const_0_4_h1', Logic(width: 4), width: 4);
      final driverName = dut.addInput('const_0_4_h1_driver', Logic());
      final bufferName = dut.addInput('passthrough_buf_0', Logic());
      dut.addOutput('out', width: 4).gets(input);
      dut.addOutput('constant', width: 4).gets(Const(1, width: 4));
      dut.addOutput('other').gets(driverName ^ bufferName);
      await dut.build();
      return dut;
    }

    String generateSv(Module dut) => SystemVerilogService(dut, register: false)
        .output
        .replaceFirst(RegExp(r' \* Generation time: [^\n]*\n'), '');
    final sv = generateSv(await makeDesign());
    final dut = await makeDesign();
    for (final cluster in [false, true]) {
      final config = NetlistSynthesizerConfiguration(
        collapseTransparentClusters: cluster,
      );
      final json = dut.generateNetlist(configuration: config);
      expect(dut.generateNetlist(configuration: config), json);
      final document = jsonDecode(json) as Map<String, dynamic>;
      final definition = (document['modules'] as Map)[dut.definitionName]
          as Map<String, dynamic>;
      final cells = definition['cells'] as Map<String, dynamic>;
      final nets = definition['netnames'] as Map<String, dynamic>;
      final ports = definition['ports'] as Map<String, dynamic>;
      expect(cells.keys.toSet().intersection({...ports.keys, ...nets.keys}),
          isEmpty);
      expect(nets.keys, containsAll(ports.keys));
      final constant = cells.entries.singleWhere(
        (entry) => (entry.value as Map)['type'] == r'$const',
      );
      expect(constant.key, startsWith('const_0_4_h1_driver_'));
      expect((constant.value as Map)['connections'], contains("4'h1"));
    }
    expect(generateSv(dut), sv);
  });

  tearDown(() async {
    await Simulator.reset();
  });

  group('driver name preference', () {
    for (final prefix in ['', '_']) {
      for (final reverse in [false, true]) {
        for (final claimed in ['none', 'driver', 'both']) {
          test('prefix="$prefix" reverse=$reverse claimed=$claimed', () async {
            final module = _DriverReceiverNames(
                driverName: '${prefix}sent', receiverName: '${prefix}received');
            await module.build();
            for (final name in [
              if (claimed != 'none') '${prefix}sent',
              if (claimed == 'both') '${prefix}received',
            ]) {
              module.namer
                  .signalNameOf(Logic(name: name, naming: Naming.mergeable));
            }
            final candidates = [module.receiver, module.driver];
            final expected = claimed == 'driver'
                ? '${prefix}received'
                : '${prefix}sent${claimed == 'both' ? '_0' : ''}';
            expect(
                module.namer.signalNameOfBest(
                    reverse ? candidates.reversed : candidates),
                expected);
            expect(module.namer.signalNameOf(module.driver), expected);
            expect(module.namer.signalNameOf(module.receiver), expected);
          });
        }
      }
    }

    for (final claimed in [false, true]) {
      test('preferred receiver beats generated driver claimed=$claimed',
          () async {
        final module = _DriverReceiverNames(driverName: '_sent');
        await module.build();
        if (claimed) {
          module.namer
              .signalNameOf(Logic(name: 'received', naming: Naming.mergeable));
        }
        expect(module.namer.signalNameOfBest([module.driver, module.receiver]),
            claimed ? 'received_0' : 'received');
      });
    }

    for (final priority in ['reserved', 'renameable', 'input', 'output']) {
      test('$priority priority remains stronger than driver preference',
          () async {
        final module = _DriverReceiverNames();
        await module.build();
        final preferred = switch (priority) {
          'input' => module.input('source'),
          'output' => module.output('observed'),
          _ => Logic(
              name: 'explicit',
              naming:
                  priority == 'reserved' ? Naming.reserved : Naming.renameable),
        };
        expect(
            module.namer
                .signalNameOfBest([module.receiver, module.driver, preferred]),
            preferred.name);
      });
    }

    for (final outputs in [false, true]) {
      test('equal-role candidates retain order outputs=$outputs', () async {
        final module = _DriverReceiverNames();
        await module.build();
        final other = _NamingStage(Logic(),
            inputName: 'otherInput', outputName: 'otherOutput');
        final first = outputs ? other.output('otherOutput') : module.receiver;
        final second = outputs ? module.driver : other.input('otherInput');
        expect(
            module.namer.signalNameOfBest([
              if (outputs) module.receiver,
              first,
              second,
            ]),
            first.name);
      });
    }

    for (final netlistFirst in [false, true]) {
      test('synthesis and simulation agree netlistFirst=$netlistFirst',
          () async {
        final module = _DriverReceiverNames();
        await module.build();
        for (final netlist in [netlistFirst, !netlistFirst]) {
          if (netlist) {
            module.generateNetlist();
          } else {
            final verilog = module.dumpSystemVerilog();
            expect(verilog, contains('logic sent;'));
            expect(verilog, contains('.sent(sent)'));
            expect(verilog, contains('.received(sent)'));
            expect(verilog, isNot(contains('logic received;')));
          }
          expect(module.namer.signalNameOfBest([module.driver]), 'sent');
          expect(module.namer.signalNameOfBest([module.receiver]), 'sent');
        }
        final vectors = [
          for (final value in [0, 1, LogicValue.x, LogicValue.z])
            Vector({'source': value},
                {'observed': value == LogicValue.z ? LogicValue.x : value}),
        ];
        await SimCompare.checkFunctionalVector(module, vectors);
        SimCompare.checkIverilogVector(module, vectors);
      });
    }
  });

  group('signalNameOfBest after netlist synthesis', () {
    test('counter — returns names after netlist synthesis', () async {
      final mod = _Counter(Logic(), Logic());
      await mod.build();
      mod.generateNetlist();

      expect(mod.namer.signalNameOfBest([mod.input('en')]), equals('en'));
      expect(mod.namer.signalNameOfBest([mod.input('reset')]), equals('reset'));
      expect(mod.namer.signalNameOfBest([mod.output('val')]), equals('val'));
    });

    test('filter_bank — returns names for sub-module signals', () async {
      const dataWidth = 16;
      const numTaps = 3;
      final clk = SimpleClockGenerator(10).clk;
      final reset = Logic(name: 'reset');
      final start = Logic(name: 'start');
      final samples = List.generate(2, (ch) => FilterSample(name: 'sample$ch'));
      final inputDone = Logic(name: 'inputDone');

      final dut = FilterBank(
        clk,
        reset,
        start,
        samples,
        inputDone,
        numTaps: numTaps,
        dataWidth: dataWidth,
        coefficients: [
          [1, 2, 1],
          [1, -2, 1],
        ],
      );
      await dut.build();
      dut.generateNetlist();

      expect(dut.namer.signalNameOfBest([dut.input('clk')]), equals('clk'));
      expect(dut.namer.signalNameOfBest([dut.input('reset')]), equals('reset'));
      expect(dut.namer.signalNameOfBest([dut.output('done')]), equals('done'));
    });
  });

  group('signalNameOfBest after SV synthesis', () {
    test('counter — returns best signal name after SV synth', () async {
      final mod = _Counter(Logic(), Logic());
      await mod.build();

      mod.dumpSystemVerilog();

      expect(mod.namer.signalNameOfBest([mod.input('en')]), equals('en'));
      expect(mod.namer.signalNameOfBest([mod.input('reset')]), equals('reset'));
    });
  });

  group('cross-synthesizer parity', () {
    test(
      'counter — SV and netlist produce identical signalNameOfBest',
      () async {
        final modNetlist = _Counter(Logic(), Logic());
        await modNetlist.build();
        modNetlist.generateNetlist();
        await Simulator.reset();

        final modSv = _Counter(Logic(), Logic());
        await modSv.build();
        modSv.dumpSystemVerilog();

        // Both paths use the same Namer, so names must match.
        final enNetlist = modNetlist.namer.signalNameOfBest([
          modNetlist.input('en'),
        ]);
        final enSv = modSv.namer.signalNameOfBest([modSv.input('en')]);

        expect(
          enSv,
          equals(enNetlist),
          reason: 'SV and netlist should produce identical canonical names',
        );
      },
    );

    test(
      'colliding mergeable names remain stable across synthesis order',
      () async {
        void runNetlist(_CollidingNames mod) => mod.generateNetlist();
        void runSv(_CollidingNames mod) => mod.dumpSystemVerilog();

        final netlistOnly = await _collisionNamesAfter([runNetlist]);
        await Simulator.reset();

        final svOnly = await _collisionNamesAfter([runSv]);
        await Simulator.reset();

        final netlistThenSv = await _collisionNamesAfter([runNetlist, runSv]);
        await Simulator.reset();

        final svThenNetlist = await _collisionNamesAfter([runSv, runNetlist]);

        expect(netlistOnly, equals(svOnly));
        expect(netlistThenSv, equals(netlistOnly));
        expect(svThenNetlist, equals(netlistOnly));

        expect(
          netlistOnly['secondDup'],
          isNot(equals(netlistOnly['firstDup'])),
        );
      },
    );

    test(
      'colliding mergeable names ignore internal signal walk order',
      () async {
        final forward = await _collisionNamesAfterSynthDefinition(
          SynthModuleDefinition.new,
        );
        await Simulator.reset();

        final reversed = await _collisionNamesAfterSynthDefinition(
          _ReverseInternalSignalOrderSynthModuleDefinition.new,
        );

        expect(reversed, equals(forward));
        expect(forward['firstDup'], equals('dup'));
        expect(forward['secondDup'], equals('dup_0'));
      },
    );

    test('colliding names stay stable when SV inlines one signal', () async {
      void runNetlist(_PartiallyInlineCollidingNames mod) =>
          mod.generateNetlist();
      void runSv(_PartiallyInlineCollidingNames mod) => mod.dumpSystemVerilog();

      final netlistOnly = await _partialInlineCollisionNamesAfter([runNetlist]);
      await Simulator.reset();

      final svOnly = await _partialInlineCollisionNamesAfter([runSv]);
      await Simulator.reset();

      final netlistThenSv = await _partialInlineCollisionNamesAfter([
        runNetlist,
        runSv,
      ]);
      await Simulator.reset();

      final svThenNetlist = await _partialInlineCollisionNamesAfter([
        runSv,
        runNetlist,
      ]);

      expect(svOnly, equals(netlistOnly));
      expect(netlistThenSv, equals(netlistOnly));
      expect(svThenNetlist, equals(netlistOnly));
      expect(netlistOnly['inlinedDup'], equals('dup'));
      expect(netlistOnly['retainedDup'], equals('dup_0'));
    });

    test(
      'signal names stay stable when SV collapses a colliding instance',
      () async {
        void runNetlist(_CollapsedInstanceCollidingNames mod) =>
            mod.generateNetlist();
        void runSv(_CollapsedInstanceCollidingNames mod) =>
            mod.dumpSystemVerilog();

        final netlistOnly = await _collapsedInstanceCollisionNamesAfter([
          runNetlist,
        ]);
        await Simulator.reset();

        final svOnly = await _collapsedInstanceCollisionNamesAfter([runSv]);
        await Simulator.reset();

        final netlistThenSv = await _collapsedInstanceCollisionNamesAfter([
          runNetlist,
          runSv,
        ]);
        await Simulator.reset();

        final svThenNetlist = await _collapsedInstanceCollisionNamesAfter([
          runSv,
          runNetlist,
        ]);

        expect(svOnly, equals(netlistOnly));
        expect(netlistThenSv, equals(netlistOnly));
        expect(svThenNetlist, equals(netlistOnly));
        expect(netlistOnly['retainedDup'], equals('dup'));
      },
    );

    test('nested typed-array names match between SV and netlist synthesis',
        () async {
      Map<String, String> names(_NestedNameModule module) => {
            'input': module.namer.signalNameOfBest([module.valuesIn]),
            'output': module.namer.signalNameOfBest([module.valuesOut]),
            'inputLanes': module.namer.signalNameOfBest([
              module.valuesIn.at([0]).lanes,
            ]),
            'outputLanes': module.namer.signalNameOfBest([
              module.valuesOut.at([1]).lanes,
            ]),
          };

      final netlistModule = _NestedNameModule();
      await netlistModule.build();
      final netlist =
          jsonDecode(netlistModule.generateNetlist()) as Map<String, dynamic>;
      final netlistModules = netlist['modules'] as Map<String, dynamic>;
      final emittedNetlistNames = {
        for (final moduleDefinition
            in netlistModules.values.cast<Map<String, dynamic>>()) ...[
          ...(moduleDefinition['ports'] as Map<String, dynamic>).keys,
          ...(moduleDefinition['netnames'] as Map<String, dynamic>).keys,
        ],
      };
      final netlistNames = names(netlistModule);
      await Simulator.reset();

      final svModule = _NestedNameModule();
      await svModule.build();
      final sv = svModule.dumpSystemVerilog();
      final svNames = names(svModule);

      expect(svNames, equals(netlistNames));
      expect(svNames['input'], 'valuesIn');
      expect(svNames['output'], 'valuesOut');
      expect(svNames['inputLanes'], 'valuesIn_0__lanes');
      expect(svNames['outputLanes'], 'valuesOut_1__lanes');
      for (final name in svNames.values) {
        expect(sv, contains(name));
        expect(emittedNetlistNames, contains(name),
            reason: 'SV and netlist should preserve signal name $name.');
      }
    });

    test('array references use canonical netlist and FLC output names',
        () async {
      SourceTracer.activate();
      addTearDown(SourceTracer.clear);
      final module = _ArrayTraceModule();
      await module.build();
      final sv = SystemVerilogService(module, register: false);
      final sc = SystemCService(module, register: false, multiFile: false);
      final trace = TraceService(module,
          svService: sv, scService: sc, packageRoot: '', register: false);
      final netlist =
          jsonDecode(module.generateNetlist()) as Map<String, dynamic>;
      final definitions = netlist['modules'] as Map<String, dynamic>;
      final definition =
          definitions[module.definitionName] as Map<String, dynamic>;
      final netnames = definition['netnames'] as Map<String, dynamic>;

      expect(netnames, containsPair('values[0]', isA<Map<String, dynamic>>()));
      expect(netnames, contains('values_0_'));
      expect(
        (netnames['values[0]'] as Map<String, dynamic>)['bits'],
        isNot((netnames['values_0_'] as Map<String, dynamic>)['bits']),
      );

      final svPosition =
          sv.singleFileSvLineMaps[module.definitionName]!['values[0]']!.first;
      final scPosition =
          sc.singleFileScLineMaps[module.definitionName]!['values[0]']!.first;
      String atPosition(String text, String position) {
        final parts = position.split(':').map(int.parse).toList();
        return text.split('\n')[parts[0] - 1].substring(parts[1] - 1);
      }

      expect(atPosition(sv.output, svPosition), startsWith('values[0]'));
      expect(
        atPosition(sc.output, scPosition),
        startsWith('sc_uint<8>(values.read().range(7, 0))'),
      );
      final keywordPosition =
          sc.singleFileScLineMaps[module.definitionName]!['namespace']!.first;
      expect(atPosition(sc.output, keywordPosition), startsWith('namespace_'));
      final symbols = <String>[];
      void collectSymbols(Object? node) {
        if (node is List) {
          node.forEach(collectSymbols);
        } else if (node is String && node.startsWith('values[0]@')) {
          symbols.add(node);
        }
      }

      final flc = trace.singleFileFlcHierarchy('${module.definitionName}.sv',
          scFilename: '${module.definitionName}.sc', packageMap: const {})!;
      final modules = flc['modules']! as Map<String, dynamic>;
      collectSymbols((modules[module.definitionName] as Map)['tree']);
      expect(symbols, hasLength(1));
      expect(symbols.single, contains('sv:$svPosition'));
      expect(symbols.single, contains('sc:$scPosition'));
    });

    test('output reference locations exclude comments and quoted text', () {
      const text = '''
// values[0]
"values[0]"
/* values[0] */ different_values[0];
instance.values[0];
out = values[0];
''';
      expect(generatedCodeReferencePositions(text, ['values[0]']),
          {'values[0]': '5:7'});
    });

    test('nested array references agree across synthesis and tracing',
        () async {
      SourceTracer.activate();
      addTearDown(SourceTracer.clear);
      final module = _NestedArrayTraceModule();
      await module.build();
      final sv = SystemVerilogService(module, register: false);
      final sc = SystemCService(module, register: false, multiFile: false);
      final trace = TraceService(module,
          svService: sv, scService: sc, packageRoot: '', register: false);
      final netlist =
          jsonDecode(module.generateNetlist()) as Map<String, dynamic>;
      final definitions = netlist['modules'] as Map<String, dynamic>;
      final netnames =
          (definitions[module.definitionName] as Map)['netnames'] as Map;
      const name = 'arr[1][0]';
      expect(netnames, contains(name));
      final svPosition =
          sv.singleFileSvLineMaps[module.definitionName]![name]!.first;
      final scPosition =
          sc.singleFileScLineMaps[module.definitionName]![name]!.first;
      final flc = trace.singleFileFlcHierarchy('${module.definitionName}.sv',
          scFilename: '${module.definitionName}.sc', packageMap: const {})!;
      expect(jsonEncode(flc), contains('$name@sv:$svPosition;sc:$scPosition'));
      expect(sv.output, contains('~$name'));
      expect(sc.output, contains('arr.read().range(23, 16)'));
    });
  });
}
