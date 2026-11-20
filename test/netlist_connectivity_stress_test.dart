// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// netlist_connectivity_stress_test.dart
// Bit-exact connectivity checks for select and aggregate rewrites.
//
// 2026 November 19
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:convert';

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class _Pair extends LogicStructure {
  Logic get low => elements[0];
  Logic get high => elements[1];

  _Pair({super.name})
      : super([Logic(name: 'low', width: 4), Logic(name: 'high', width: 4)]);

  @override
  _Pair clone({String? name}) => _Pair(name: name);
}

class _Envelope extends LogicStructure {
  _Pair get payload => elements[0] as _Pair;
  Logic get tail => elements[1];

  _Envelope({super.name})
      : super([_Pair(name: 'payload'), Logic(name: 'tail', width: 4)]);

  @override
  _Envelope clone({String? name}) => _Envelope(name: name);
}

class _ConnectivityStress extends Module {
  _ConnectivityStress(
    Logic vector,
    Logic cleanup,
    LogicArray array,
    _Pair pair,
    _Envelope nested,
  ) : super(definitionName: 'ConnectivityStress') {
    vector = addInput('vector', vector, width: 16);
    cleanup = addInput('cleanup', cleanup, width: 8);
    array = addInputArray(
      'array',
      array,
      dimensions: [4],
      elementWidth: 4,
    );
    pair = addTypedInput('pair', pair);
    nested = addTypedInput('nested', nested);

    final low = vector.getRange(0, 4).named('low', naming: Naming.mergeable);
    final mid = vector.getRange(4, 8).named('mid', naming: Naming.mergeable);
    final high = vector.getRange(8, 12).named('high', naming: Naming.mergeable);
    final top = vector.getRange(12, 16).named('top', naming: Naming.mergeable);
    addOutput('adjacent', width: 8) <= [mid, low].concat();
    addOutput('permuted', width: 16) <= [low, top, mid, high].concat();
    addOutput('overlap', width: 8) <=
        [vector.getRange(2, 6), vector.getRange(4, 8)].concat();
    final firstConcat = [vector.getRange(8, 12), array.elements[0]]
        .concat()
        .named('firstConcat', naming: Naming.renameable);
    final secondConcat = [pair.high, vector.getRange(0, 4)]
        .concat()
        .named('secondConcat', naming: Naming.renameable);
    addOutput('concatOfConcats', width: 16) <=
        [firstConcat, secondConcat].concat();
    final firstSlice =
        vector.getRange(3, 14).named('firstSlice', naming: Naming.renameable);
    addOutput('sliceOfSlice', width: 6) <= firstSlice.getRange(2, 8);
    final mixedConcat = [firstConcat, secondConcat]
        .concat()
        .named('mixedConcat', naming: Naming.renameable);
    addOutput('sliceOfConcat', width: 12) <= mixedConcat.getRange(2, 14);
    final cleanupLow =
        cleanup.getRange(0, 4).named('cleanupLow', naming: Naming.mergeable);
    final cleanupHigh =
        cleanup.getRange(4, 8).named('cleanupHigh', naming: Naming.mergeable);
    addOutput('cleanupOut', width: 8) <= [cleanupHigh, cleanupLow].concat();

    final regrouped = LogicArray([2], 8, name: 'regrouped');
    regrouped.elements[0] <= [array.elements[2], array.elements[0]].concat();
    regrouped.elements[1] <= [pair.high, array.elements[1]].concat();
    addOutput('regrouped', width: 16) <= regrouped;
    addOutput('arrayTap', width: 4) <= array.elements[2];
    addOutput('fields', width: 8) <= [pair.low, pair.high].concat();

    final outputArray =
        addOutputArray('arrayOut', dimensions: [4], elementWidth: 4);
    outputArray.elements[0] <= pair.high;
    outputArray.elements[1] <= array.elements[3];
    outputArray.elements[2] <= low;
    outputArray.elements[3] <= pair.low;

    final result = _Pair(name: 'result');
    result.low <= array.elements[2];
    result.high <= pair.low;
    addTypedOutput('pairOut', result.clone) <= result;

    final assembled = _Envelope(name: 'assembled');
    assembled.payload.low <= nested.payload.high;
    assembled.payload.high <= nested.tail;
    assembled.tail <= array.elements[2];
    addOutput('nestedFieldSlice', width: 2) <=
        nested.payload.high.getRange(1, 3);
    addOutput('builtFields', width: 8) <=
        [assembled.tail, assembled.payload.low].concat();
    final rebuilt = _Envelope(name: 'rebuilt');
    rebuilt.payload.low <= assembled.payload.high;
    rebuilt.payload.high <= pair.high;
    rebuilt.tail <= assembled.payload.low;
    addTypedOutput('nestedOut', rebuilt.clone) <= rebuilt;
  }
}

class _ConnectivityStressParent extends Module {
  _ConnectivityStressParent(
    Logic vector,
    Logic cleanup,
    LogicArray array,
    _Pair pair,
    _Envelope nested,
  ) : super(definitionName: 'ConnectivityStressParent') {
    vector = addInput('vector', vector, width: 16);
    cleanup = addInput('cleanup', cleanup, width: 8);
    array = addInputArray(
      'array',
      array,
      dimensions: [4],
      elementWidth: 4,
    );
    pair = addTypedInput('pair', pair);
    nested = addTypedInput('nested', nested);
    final childArray = LogicArray([4], 4, name: 'childArray');
    childArray.elements[0] <= array.elements[3];
    childArray.elements[1] <= pair.high;
    childArray.elements[2] <= array.elements[0];
    childArray.elements[3] <= vector.getRange(12, 16);
    final childPair = _Pair(name: 'childPair');
    childPair.low <= array.elements[0];
    childPair.high <= pair.low;
    final child =
        _ConnectivityStress(vector, cleanup, childArray, childPair, nested);
    for (final name in [
      'adjacent',
      'permuted',
      'overlap',
      'concatOfConcats',
      'sliceOfSlice',
      'sliceOfConcat',
      'cleanupOut',
      'regrouped',
      'arrayTap',
      'fields',
      'nestedFieldSlice',
      'builtFields',
    ]) {
      final output = child.output(name);
      addOutput(name, width: output.width) <= output;
    }
    addOutputArray('arrayOut', dimensions: [4], elementWidth: 4)
        .gets(child.output('arrayOut'));
    addTypedOutput('pairOut', _Pair.new).gets(child.output('pairOut'));
    addTypedOutput('nestedOut', _Envelope.new).gets(child.output('nestedOut'));
  }
}

class _BusSubsetSelections extends Module {
  _BusSubsetSelections(Logic data, {String? onlyOutput})
      : super(definitionName: 'BusSubsetSelections') {
    data = addInput('data', data, width: 8);
    Logic intermediate() => BusSubset(data, 2, 6)
        .subset
        .named('intermediate', naming: Naming.renameable);
    final outputs = <String, Logic Function()>{
      'forward': () => BusSubset(data, 1, 3).subset,
      'reverseInside': () => BusSubset(data, 3, 1).subset,
      'reverseOutside': () => BusSubset(data, 6, 3).subset,
      'reverseFull': () => BusSubset(data, 7, 0).subset,
      'single': () => BusSubset(data, 5, 5).subset,
      'reverseNested': () => BusSubset(intermediate(), 3, 1).subset,
      'reverseTwice': () {
        final reversed = BusSubset(intermediate(), 4, 0)
            .subset
            .named('reverseTwiceInput', naming: Naming.renameable);
        return BusSubset(reversed, 4, 0).subset;
      },
      'combined': () => [
            BusSubset(data, 3, 1).subset,
            BusSubset(data, 1, 3).subset,
          ].concat(),
      'reverseAdjacent': () => [
            BusSubset(data, 3, 2).subset,
            BusSubset(data, 5, 4).subset,
          ].concat(),
      'reverseConcat': () => BusSubset(
            [data.getRange(0, 4), data.getRange(4, 8)].concat(),
            5,
            2,
          ).subset,
    };
    for (final entry in outputs.entries) {
      if (onlyOutput == null || onlyOutput == entry.key) {
        final value = entry.value();
        addOutput(entry.key, width: value.width) <= value;
      }
    }
  }
}

class _BusSubsetParent extends Module {
  _BusSubsetParent(Logic data, String onlyOutput)
      : super(definitionName: 'BusSubsetParent') {
    data = addInput('data', data, width: 8);
    final child = _BusSubsetSelections(data, onlyOutput: onlyOutput);
    final output = child.output(onlyOutput);
    addOutput(onlyOutput, width: output.width) <= output;
  }
}

typedef _Source = ({String port, int bit});

/// Traces transparent cell outputs back to input-port bits.
Map<String, List<_Source>> _traceOutputs(
  Map<String, dynamic> module,
  Map<String, dynamic> modules,
) {
  final ports = module['ports'] as Map<String, dynamic>;
  final cells = module['cells'] as Map<String, dynamic>;
  final inputs = <int, _Source>{};
  final drivers = <int, ({Object source, String cell})>{};

  void connect(Object output, Object source, String cell) {
    if (output is! int) {
      throw StateError('$cell has a non-wire output: $output');
    }
    if (drivers.containsKey(output)) {
      throw StateError(
        '$cell ($source) and ${drivers[output]!.cell} '
        '(${drivers[output]!.source}) both drive bit $output: '
        '${cells[cell]} / ${cells[drivers[output]!.cell]}',
      );
    }
    drivers[output] = (source: source, cell: cell);
  }

  for (final entry in ports.entries) {
    final port = entry.value as Map<String, dynamic>;
    if (port['direction'] != 'input') {
      continue;
    }
    final bits = (port['bits'] as List).cast<int>();
    for (final (index, bit) in bits.indexed) {
      if (inputs.containsKey(bit)) {
        throw StateError('Input ports share bit $bit');
      }
      inputs[bit] = (port: entry.key, bit: index);
    }
  }

  for (final entry in cells.entries) {
    final cell = entry.value as Map<String, dynamic>;
    final type = cell['type'] as String;
    final conns = cell['connections'] as Map<String, dynamic>;
    final dirs = cell['port_directions'] as Map<String, dynamic>;
    final params = cell['parameters'] as Map<String, dynamic>;
    final name = entry.key;

    void mapBits(List<dynamic> output, List<dynamic> source) {
      if (output.length != source.length) {
        throw StateError('$name has mismatched output and input widths');
      }
      for (var i = 0; i < output.length; i++) {
        connect(output[i] as Object, source[i] as Object, name);
      }
    }

    switch (type) {
      case r'$buf':
        mapBits(conns['Y'] as List, conns['A'] as List);
      case r'$slice':
        final input = conns['A'] as List;
        final output = conns['Y'] as List;
        final offset = params['OFFSET'] as int;
        if (offset < 0 || offset + output.length > input.length) {
          throw StateError('$name selects beyond its input');
        }
        mapBits(output, input.sublist(offset, offset + output.length));
      case r'$concat':
        final names = dirs.entries
            .where((port) => port.value == 'input')
            .map((port) => port.key)
            .toList();
        int offset(String port) {
          if (port == 'A') {
            return 0;
          }
          if (port == 'B') {
            return (conns['A'] as List).length;
          }
          final match = RegExp(r'^\[(\d+)(?::(\d+))?\]$').firstMatch(port);
          if (match == null) {
            throw StateError('$name has unknown port $port');
          }
          return int.parse(match.group(2) ?? match.group(1)!);
        }

        names.sort((a, b) => offset(a).compareTo(offset(b)));
        mapBits(
          conns['Y'] as List,
          [for (final port in names) ...(conns[port] as List)],
        );
      case r'$struct_unpack':
        final input = conns['A'] as List;
        for (var i = 0; i < (params['FIELD_COUNT'] as int); i++) {
          final port = params['FIELD_${i}_NAME'] as String;
          final offset = params['FIELD_${i}_OFFSET'] as int;
          final width = params['FIELD_${i}_WIDTH'] as int;
          mapBits(conns[port] as List, input.sublist(offset, offset + width));
        }
      case r'$struct_pack':
        final output = conns['Y'] as List;
        for (var i = 0; i < (params['FIELD_COUNT'] as int); i++) {
          final port = params['FIELD_${i}_NAME'] as String;
          final offset = params['FIELD_${i}_OFFSET'] as int;
          final width = params['FIELD_${i}_WIDTH'] as int;
          mapBits(output.sublist(offset, offset + width), conns[port] as List);
        }
      default:
        final child = modules[type];
        if (child is! Map<String, dynamic>) {
          throw StateError('Unexpected cell $name ($type)');
        }
        final childOutputs = _traceOutputs(child, modules);
        for (final output in childOutputs.entries) {
          final sources = [
            for (final source in output.value)
              (conns[source.port] as List)[source.bit],
          ];
          mapBits(conns[output.key] as List, sources);
        }
    }
  }

  _Source trace(Object bit, Set<int> path) {
    if (bit is! int) {
      throw StateError('Unexpected constant $bit');
    }
    if (!path.add(bit)) {
      throw StateError('Connectivity cycle at bit $bit');
    }
    final input = inputs[bit];
    if (input != null) {
      if (drivers.containsKey(bit)) {
        throw StateError('Input bit $bit also has a cell driver');
      }
      return input;
    }
    final source = drivers[bit];
    if (source == null) {
      final users = cells.entries
          .where((entry) {
            final conns =
                (entry.value as Map<String, dynamic>)['connections'] as Map;
            return conns.values.any((bits) => (bits as List).contains(bit));
          })
          .map((entry) => '${entry.key}: ${entry.value}')
          .join('\n');
      throw StateError('Undriven bit $bit, path $path\n$users');
    }
    return trace(source.source, path);
  }

  return {
    for (final entry in ports.entries)
      if ((entry.value as Map<String, dynamic>)['direction'] == 'output')
        entry.key: [
          for (final bit
              in (entry.value as Map<String, dynamic>)['bits'] as List)
            trace(bit as Object, <int>{}),
        ],
  };
}

List<_Source> _bits(String port, Iterable<int> indices) =>
    [for (final bit in indices) (port: port, bit: bit)];

Iterable<int> _range(int start, int end) =>
    Iterable.generate(end - start, (i) => start + i);

final _busSubsetExpected = <String, List<_Source>>{
  'forward': _bits('data', [1, 2, 3]),
  'reverseInside': _bits('data', [3, 2, 1]),
  'reverseOutside': _bits('data', [6, 5, 4, 3]),
  'reverseFull': _bits('data', [7, 6, 5, 4, 3, 2, 1, 0]),
  'single': _bits('data', [5]),
  'reverseNested': _bits('data', [5, 4, 3]),
  'reverseTwice': _bits('data', [2, 3, 4, 5, 6]),
  'combined': _bits('data', [1, 2, 3, 3, 2, 1]),
  'reverseAdjacent': _bits('data', [5, 4, 3, 2]),
  'reverseConcat': _bits('data', [1, 0, 7, 6]),
};

final _expected = <String, List<_Source>>{
  'adjacent': _bits('vector', _range(0, 8)),
  'permuted': _bits('vector', [
    ..._range(8, 12),
    ..._range(4, 8),
    ..._range(12, 16),
    ..._range(0, 4),
  ]),
  'overlap': _bits('vector', [..._range(4, 8), ..._range(2, 6)]),
  'concatOfConcats': [
    ..._bits('vector', _range(0, 4)),
    ..._bits('pair', _range(4, 8)),
    ..._bits('array', _range(0, 4)),
    ..._bits('vector', _range(8, 12)),
  ],
  'sliceOfSlice': _bits('vector', _range(5, 11)),
  'sliceOfConcat': [
    ..._bits('vector', _range(2, 4)),
    ..._bits('pair', _range(4, 8)),
    ..._bits('array', _range(0, 4)),
    ..._bits('vector', _range(8, 10)),
  ],
  'cleanupOut': _bits('cleanup', _range(0, 8)),
  'regrouped': [
    ..._bits('array', _range(0, 4)),
    ..._bits('array', _range(8, 12)),
    ..._bits('array', _range(4, 8)),
    ..._bits('pair', _range(4, 8)),
  ],
  'arrayTap': _bits('array', _range(8, 12)),
  'fields': _bits('pair', [..._range(4, 8), ..._range(0, 4)]),
  'arrayOut': [
    ..._bits('pair', _range(4, 8)),
    ..._bits('array', _range(12, 16)),
    ..._bits('vector', _range(0, 4)),
    ..._bits('pair', _range(0, 4)),
  ],
  'pairOut': [
    ..._bits('array', _range(8, 12)),
    ..._bits('pair', _range(0, 4)),
  ],
  'nestedFieldSlice': _bits('nested', _range(5, 7)),
  'builtFields': [
    ..._bits('nested', _range(4, 8)),
    ..._bits('array', _range(8, 12)),
  ],
  'nestedOut': [
    ..._bits('nested', _range(8, 12)),
    ..._bits('pair', _range(4, 8)),
    ..._bits('nested', _range(4, 8)),
  ],
};

final _hierarchicalExpected = {
  for (final entry in _expected.entries)
    entry.key: [
      for (final source in entry.value)
        switch ((source.port, source.bit ~/ 4)) {
          ('array', 0) => (port: 'array', bit: source.bit + 12),
          ('array', 1) => (port: 'pair', bit: source.bit),
          ('array', 2) => (port: 'array', bit: source.bit - 8),
          ('array', 3) => (port: 'vector', bit: source.bit),
          ('pair', 0) => (port: 'array', bit: source.bit),
          ('pair', 1) => (port: 'pair', bit: source.bit - 4),
          _ => source,
        },
    ],
};

void main() {
  tearDown(Simulator.reset);

  for (final collapse in [false, true]) {
    test(
        'omitting metadata preserves the complete netlist (collapse=$collapse)',
        () async {
      SourceTracer.activate();
      addTearDown(SourceTracer.clear);
      final module = _ConnectivityStress(Logic(width: 16), Logic(width: 8),
          LogicArray([4], 4), _Pair(), _Envelope());
      await module.build();

      Map<String, dynamic> emit({required bool omitMetadata}) =>
          jsonDecode(NetlistSynthesizer(
            configuration: NetlistSynthesizerConfiguration(
              collapseTransparentClusters: collapse,
              trace: true,
              omitRohdMetadata: omitMetadata,
            ),
          ).synthesizeToJson(module)) as Map<String, dynamic>;

      final normal = emit(omitMetadata: false);
      final stripped = emit(omitMetadata: true);
      expect(normal.remove('files'), isNotEmpty);
      final normalModules = normal['modules'] as Map<String, dynamic>;
      var syntheticCells = 0;
      var typedEntries = 0;
      var traces = 0;
      for (final value in normalModules.values) {
        final definition = value as Map<String, dynamic>;
        final attributes = definition['attributes'] as Map<String, dynamic>;
        if (attributes.remove('rohd.src_trace') != null) {
          traces++;
        }
        for (final section in ['ports', 'netnames']) {
          for (final entry in (definition[section] as Map).values) {
            if ((entry as Map).remove('logic_type') != null) {
              typedEntries++;
            }
          }
        }
        for (final entry in (definition['cells'] as Map).values) {
          final cell = entry as Map;
          if (cell.remove('is_synthetic') != null) {
            syntheticCells++;
          }
          cell.remove('synthetic_origin');
        }
      }
      expect(syntheticCells, greaterThan(0));
      expect(typedEntries, greaterThan(0));
      expect(traces, greaterThan(0));
      expect(stripped, equals(normal));
    });
  }

  test('individual netlist files also omit metadata without changing wiring',
      () async {
    final module = _ConnectivityStress(Logic(width: 16), Logic(width: 8),
        LogicArray([4], 4), _Pair(), _Envelope());
    await module.build();

    Map<String, Map<String, dynamic>> files({required bool omitMetadata}) {
      final synth = NetlistSynthesizer(
        configuration:
            NetlistSynthesizerConfiguration(omitRohdMetadata: omitMetadata),
      );
      return {
        for (final file in SynthBuilder(module, synth).getSynthFileContents())
          file.name: jsonDecode(file.contents) as Map<String, dynamic>,
      };
    }

    final original = files(omitMetadata: false);
    final stripped = files(omitMetadata: true);
    var syntheticCells = 0;
    for (final document in original.values) {
      for (final value
          in (document['modules'] as Map<String, dynamic>).values) {
        final definition = value as Map<String, dynamic>;
        for (final section in ['ports', 'netnames']) {
          for (final entry
              in (definition[section] as Map<String, dynamic>).values) {
            (entry as Map<String, dynamic>).remove('logic_type');
          }
        }
        for (final entry
            in (definition['cells'] as Map<String, dynamic>).values) {
          final cell = entry as Map<String, dynamic>;
          if (cell.remove('is_synthetic') != null) {
            syntheticCells++;
          }
          cell.remove('synthetic_origin');
        }
      }
    }
    expect(syntheticCells, greaterThan(0));
    expect(stripped, equals(original));
  });

  test('bus subset oracle agrees with ROHD and SystemVerilog simulation',
      () async {
    final module = _BusSubsetSelections(Logic(width: 8));
    await module.build();
    final vectors = [
      for (var inputBit = 0; inputBit < 8; inputBit++)
        Vector(
          {'data': 1 << inputBit},
          {
            for (final output in _busSubsetExpected.entries)
              output.key: output.value.indexed.fold<int>(
                0,
                (value, bit) =>
                    value | (bit.$2.bit == inputBit ? 1 << bit.$1 : 0),
              ),
          },
        ),
    ];
    await SimCompare.checkFunctionalVector(module, vectors);
    SimCompare.checkIverilogVector(module, vectors);
  });

  for (final entry in _busSubsetExpected.entries) {
    for (final dce in [false, true]) {
      for (final collapse in [false, true]) {
        for (final hierarchical in [false, true]) {
          test(
              'bus subset ${entry.key} bit mapping '
              '(DCE=$dce, collapse=$collapse, hierarchy=$hierarchical)',
              () async {
            final module = hierarchical
                ? _BusSubsetParent(Logic(width: 8), entry.key)
                : _BusSubsetSelections(Logic(width: 8), onlyOutput: entry.key);
            await module.build();
            final synthesizer = NetlistSynthesizer(
              configuration: NetlistSynthesizerConfiguration(
                enableDeadCellElimination: dce,
                collapseTransparentClusters: collapse,
              ),
            );
            final json =
                jsonDecode(synthesizer.synthesizeToJson(module)) as Map;
            final modules = json['modules'] as Map<String, dynamic>;
            final definition =
                modules[module.definitionName] as Map<String, dynamic>;
            expect(
                _traceOutputs(definition, modules), {entry.key: entry.value});
          });
        }
      }
    }
  }

  for (final hierarchical in [false, true]) {
    test('stress simulation agrees with the oracle (hierarchy=$hierarchical)',
        () async {
      final vector = Logic(width: 16);
      final cleanup = Logic(width: 8);
      final array = LogicArray([4], 4);
      final pair = _Pair();
      final nested = _Envelope();
      final inputs = {
        'vector': vector,
        'cleanup': cleanup,
        'array': array,
        'pair': pair,
        'nested': nested,
      };
      final module = hierarchical
          ? _ConnectivityStressParent(vector, cleanup, array, pair, nested)
          : _ConnectivityStress(vector, cleanup, array, pair, nested);
      final expectedOutputs = hierarchical ? _hierarchicalExpected : _expected;
      await module.build();
      for (final input in inputs.values) {
        input.put(0);
      }
      final simulation = Simulator.run();
      await Simulator.tick();
      for (final input in inputs.entries) {
        for (var bit = 0; bit < input.value.width; bit++) {
          input.value.put(1 << bit);
          await Simulator.tick();
          for (final output in expectedOutputs.entries) {
            var expected = 0;
            for (final (index, source) in output.value.indexed) {
              if (source.port == input.key && source.bit == bit) {
                expected |= 1 << index;
              }
            }
            expect(module.output(output.key).value.toInt(), expected,
                reason: '${input.key}[$bit] -> ${output.key}');
          }
          await simulation;
          input.value.put(0);
          await Simulator.tick();
        }
      }
    });
  }

  test('bit tracer detects cycles, disconnected wires, and permutations',
      () async {
    final module = _ConnectivityStress(Logic(width: 16), Logic(width: 8),
        LogicArray([4], 4), _Pair(), _Envelope());
    await module.build();
    final json =
        jsonDecode(NetlistSynthesizer().synthesizeToJson(module)) as Map;
    final modules = json['modules'] as Map<String, dynamic>;
    final definition = modules[module.definitionName] as Map<String, dynamic>;
    final ports = definition['ports'] as Map<String, dynamic>;
    final outputBits = (ports['cleanupOut'] as Map)['bits'] as List;
    final cells = definition['cells'] as Map<String, dynamic>;
    final concat =
        cells.values.cast<Map<String, dynamic>>().singleWhere((cell) {
      final output = (cell['connections'] as Map)['Y'];
      return output is List &&
          output.length == outputBits.length &&
          output.indexed.every((entry) => entry.$2 == outputBits[entry.$1]);
    });
    final input = (concat['connections'] as Map)['A'] as List;
    final original = List<Object>.from(input);

    input[0] = outputBits[0];
    expect(() => _traceOutputs(definition, modules), throwsStateError);
    input[0] = 1000000;
    expect(() => _traceOutputs(definition, modules), throwsStateError);
    input[0] = original[1];
    input[1] = original[0];
    expect(_traceOutputs(definition, modules)['cleanupOut'],
        isNot(equals(_expected['cleanupOut'])));
  });

  for (final dce in [false, true]) {
    for (final collapse in [false, true]) {
      for (final hierarchical in [false, true]) {
        test(
            'select/concat connectivity '
            '(DCE=$dce, collapse=$collapse, hierarchy=$hierarchical)',
            () async {
          final module = hierarchical
              ? _ConnectivityStressParent(Logic(width: 16), Logic(width: 8),
                  LogicArray([4], 4), _Pair(), _Envelope())
              : _ConnectivityStress(Logic(width: 16), Logic(width: 8),
                  LogicArray([4], 4), _Pair(), _Envelope());
          await module.build();
          final synthesizer = NetlistSynthesizer(
            configuration: NetlistSynthesizerConfiguration(
              enableDeadCellElimination: dce,
              collapseTransparentClusters: collapse,
            ),
          );
          final json = jsonDecode(synthesizer.synthesizeToJson(module)) as Map;
          final modules = json['modules'] as Map<String, dynamic>;
          final definition =
              modules[module.definitionName] as Map<String, dynamic>;
          final stressDef =
              modules['ConnectivityStress'] as Map<String, dynamic>;
          final stressCells = (stressDef['cells'] as Map<String, dynamic>)
              .values
              .cast<Map<String, dynamic>>();
          final ports = stressDef['ports'] as Map<String, dynamic>;
          final netnames = stressDef['netnames'] as Map<String, dynamic>;
          List<dynamic> bits(Map<String, dynamic> names, String name) =>
              (names[name] as Map)['bits'] as List;
          Map<String, dynamic> cellDriving(List<dynamic> expected) =>
              stressCells.singleWhere((cell) {
                final output = (cell['connections'] as Map)['Y'];
                return output is List &&
                    output.length == expected.length &&
                    output.indexed
                        .every((entry) => entry.$2 == expected[entry.$1]);
              });

          final cleanupCell = cellDriving(bits(ports, 'cleanupOut'));
          expect(cleanupCell['type'], collapse ? r'$slice' : r'$concat');
          if (!collapse) {
            final nestedConcat = cellDriving(bits(ports, 'concatOfConcats'));
            expect(nestedConcat['type'], r'$concat');
            final concatInputs = nestedConcat['connections'] as Map;
            expect(concatInputs['A'], bits(netnames, 'secondConcat'));
            expect(concatInputs['B'], bits(netnames, 'firstConcat'));
            expect(
                cellDriving(bits(netnames, 'firstConcat'))['type'], r'$concat');
            expect(cellDriving(bits(netnames, 'secondConcat'))['type'],
                r'$concat');

            final secondSlice = cellDriving(bits(ports, 'sliceOfSlice'));
            expect(secondSlice['type'], r'$slice');
            expect((secondSlice['connections'] as Map)['A'],
                bits(netnames, 'firstSlice'));
            expect(
                cellDriving(bits(netnames, 'firstSlice'))['type'], r'$slice');

            final concatSlice = cellDriving(bits(ports, 'sliceOfConcat'));
            expect(concatSlice['type'], r'$slice');
            expect((concatSlice['connections'] as Map)['A'],
                bits(netnames, 'mixedConcat'));
            expect(
                cellDriving(bits(netnames, 'mixedConcat'))['type'], r'$concat');
          }
          final actual = _traceOutputs(definition, modules);
          expect(actual, hierarchical ? _hierarchicalExpected : _expected);
        });
      }
    }
  }
}
