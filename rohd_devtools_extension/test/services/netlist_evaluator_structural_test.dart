// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// netlist_evaluator_structural_test.dart
// Tests NetlistEvaluator structural evaluation.
//
// 2026 October 22
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter_test/flutter_test.dart';
import 'package:rohd/rohd.dart' show LogicValue;
import 'package:rohd_devtools_extension/rohd_devtools/services/netlist_evaluator.dart';

Map<String, dynamic> _signal(List<int> bits) => {'bits': bits};

Map<String, dynamic> _cell({
  required String type,
  required Map<String, dynamic> connections,
  required Map<String, dynamic> directions,
  Map<String, dynamic> parameters = const {},
}) =>
    {
      'type': type,
      'connections': connections,
      'port_directions': directions,
      'parameters': parameters,
    };

Map<String, dynamic> _topModule({
  required Map<String, dynamic> ports,
  required Map<String, dynamic> netnames,
  required Map<String, dynamic> cells,
}) =>
    {
      'top': {
        'attributes': {'top': 1},
        'ports': ports,
        'netnames': netnames,
        'cells': cells,
      },
    };

({String value, int width}) _evaluate(
  Map<String, dynamic> modules,
  String signal, {
  required Map<String, String> snapshot,
  EvalOnDemandCache? cache,
}) {
  final result = evaluateSignalOnDemand(
    modules: modules,
    rerootedPath: 'top/$signal',
    snapshotLookup: (path) => snapshot[path],
    evalCache: cache,
  );
  expect(result, isNotNull);
  return result!;
}

void _expectValue(
  ({String value, int width}) actual,
  int value,
  int width,
) {
  expect(actual.width, width);
  expect(parseHexToLV(actual.value, width), LogicValue.ofInt(value, width));
}

void main() {
  test('evaluates concat and slice-style structural cells', () {
    final concatModules = _topModule(
      ports: {
        'a': _signal([1, 2]),
        'b': _signal([3, 4]),
        'out': _signal([5, 6, 7, 8]),
      },
      netnames: {
        'a': _signal([1, 2]),
        'b': _signal([3, 4]),
        'out': _signal([5, 6, 7, 8]),
      },
      cells: {
        'concat': _cell(
          type: r'$concat',
          connections: {
            'A': [1, 2],
            'B': [3, 4],
            'Y': [5, 6, 7, 8],
          },
          directions: {'A': 'input', 'B': 'input', 'Y': 'output'},
        ),
      },
    );
    _expectValue(
      _evaluate(
        concatModules,
        'out',
        snapshot: {'top/a': "2'b01", 'top/b': "2'b10"},
      ),
      9,
      4,
    );
    final concatEvaluator = NetlistEvaluator(concatModules);
    expect(concatEvaluator.isComputed('top/out'), isTrue);
    expect(concatEvaluator.isComputed('top/missing'), isFalse);
    expect(concatEvaluator.canEvaluate('top/out'), isTrue);
    expect(concatEvaluator.canEvaluate('top/missing'), isTrue);
    expect(concatEvaluator.signalWidth('top/out'), 4);
    expect(concatEvaluator.signalWidth('top/missing'), 0);
    expect(
      concatEvaluator.collectLeaves('top/out'),
      containsAll(['top/a', 'top/b']),
    );
    expect(concatEvaluator.allEvaluablePaths('top'), contains('top/out'));

    final sliceModules = _topModule(
      ports: {
        'a': _signal([1, 2, 3, 4]),
        'out': _signal([5, 6]),
      },
      netnames: {
        'a': _signal([1, 2, 3, 4]),
        'out': _signal([5, 6]),
      },
      cells: {
        'slice': _cell(
          type: r'$slice',
          connections: {
            'A': [1, 2, 3, 4],
            'Y': [5, 6],
          },
          directions: {'A': 'input', 'Y': 'output'},
          parameters: {'OFFSET': 1},
        ),
      },
    );
    _expectValue(
      _evaluate(
        sliceModules,
        'out',
        snapshot: {'top/a': "4'hd"},
      ),
      2,
      2,
    );

    final preSlicedModules = _topModule(
      ports: {
        'a': _signal([1, 2, 3, 4]),
        'out': _signal([5, 6]),
      },
      netnames: {
        'a': _signal([1, 2, 3, 4]),
        'out': _signal([5, 6]),
      },
      cells: {
        'field': _cell(
          type: r'$struct_field',
          connections: {
            'A': [2, 3],
            'Y': [5, 6],
          },
          directions: {'A': 'input', 'Y': 'output'},
          parameters: {'OFFSET': 8},
        ),
      },
    );
    _expectValue(
      _evaluate(
        preSlicedModules,
        'out',
        snapshot: {'top/a': "4'hd"},
      ),
      2,
      2,
    );
  });

  test('evaluates struct unpack and pack cells', () {
    final unpackModules = _topModule(
      ports: {
        'packed': _signal([1, 2, 3, 4]),
        'low': _signal([5, 6]),
        'high': _signal([7, 8]),
      },
      netnames: {
        'packed': _signal([1, 2, 3, 4]),
        'low': _signal([5, 6]),
        'high': _signal([7, 8]),
      },
      cells: {
        'unpack': _cell(
          type: r'$struct_unpack',
          connections: {
            'A': [1, 2, 3, 4],
            'low': [5, 6],
            'high': [7, 8],
          },
          directions: {'A': 'input', 'low': 'output', 'high': 'output'},
          parameters: {
            'FIELD_COUNT': 2,
            'FIELD_0_NAME': 'low',
            'FIELD_0_OFFSET': 0,
            'FIELD_0_WIDTH': 2,
            'FIELD_1_NAME': 'high',
            'FIELD_1_OFFSET': 2,
            'FIELD_1_WIDTH': 2,
          },
        ),
      },
    );
    _expectValue(
      _evaluate(
        unpackModules,
        'low',
        snapshot: {'top/packed': "4'hd"},
      ),
      1,
      2,
    );
    _expectValue(
      _evaluate(
        unpackModules,
        'high',
        snapshot: {'top/packed': "4'hd"},
      ),
      3,
      2,
    );

    final packModules = _topModule(
      ports: {
        'low': _signal([1, 2]),
        'high': _signal([3, 4]),
        'packed': _signal([5, 6, 7, 8]),
      },
      netnames: {
        'low': _signal([1, 2]),
        'high': _signal([3, 4]),
        'packed': _signal([5, 6, 7, 8]),
      },
      cells: {
        'pack': _cell(
          type: r'$struct_pack',
          connections: {
            'low': [1, 2],
            'high': [3, 4],
            'Y': [5, 6, 7, 8],
          },
          directions: {'low': 'input', 'high': 'input', 'Y': 'output'},
          parameters: {
            'FIELD_COUNT': 2,
            'FIELD_0_NAME': 'low',
            'FIELD_0_OFFSET': 0,
            'FIELD_0_WIDTH': 2,
            'FIELD_1_NAME': 'high',
            'FIELD_1_OFFSET': 2,
            'FIELD_1_WIDTH': 2,
          },
        ),
      },
    );
    _expectValue(
      _evaluate(
        packModules,
        'packed',
        snapshot: {'top/low': "2'b01", 'top/high': "2'b10"},
      ),
      9,
      4,
    );
  });

  test('uses DFF and submodule output snapshots and resets cached values', () {
    final modules = {
      ..._topModule(
        ports: {
          'd': _signal([1, 2]),
          'q': _signal([3, 4]),
          'childOut': _signal([5, 6]),
        },
        netnames: {
          'd': _signal([1, 2]),
          'q': _signal([3, 4]),
          'childOut': _signal([5, 6]),
        },
        cells: {
          'ff': _cell(
            type: r'$dff',
            connections: {
              'D': [1, 2],
              'C': ['0'],
              'Q': [3, 4],
            },
            directions: {'D': 'input', 'C': 'input', 'Q': 'output'},
          ),
          'child': _cell(
            type: 'Child',
            connections: {
              'O': [5, 6],
            },
            directions: {'O': 'output'},
          ),
        },
      ),
      'Child': {
        'ports': {
          'O': _signal([1, 2]),
        },
        'netnames': {
          'O': _signal([1, 2]),
        },
        'cells': <String, dynamic>{},
      },
    };
    final cache = EvalOnDemandCache();
    final snapshot = <String, String>{
      'top/ff/Q': "2'b11",
      'top/child/O': "2'b10",
    };
    _expectValue(
      _evaluate(modules, 'q', snapshot: snapshot, cache: cache),
      3,
      2,
    );
    _expectValue(
      _evaluate(modules, 'childOut', snapshot: snapshot, cache: cache),
      2,
      2,
    );

    snapshot['top/child/O'] = "2'b01";
    _expectValue(
      _evaluate(modules, 'childOut', snapshot: snapshot, cache: cache),
      2,
      2,
    );
    cache.clear();
    _expectValue(
      _evaluate(modules, 'childOut', snapshot: snapshot, cache: cache),
      1,
      2,
    );
  });

  test('rebuilds stale indexes when a slim module gains connectivity', () {
    final gate = <String, dynamic>{'type': r'$and'};
    final modules = _topModule(
      ports: {
        'a': _signal([1]),
        'b': _signal([2]),
        'out': _signal([3]),
      },
      netnames: {
        'a': _signal([1]),
        'b': _signal([2]),
        'out': _signal([3]),
      },
      cells: {'gate': gate},
    );
    final evaluator = NetlistEvaluator(modules);
    expect(evaluator.canEvaluate('top/out'), isFalse);

    gate
      ..['connections'] = {
        'A': [1],
        'B': [2],
        'Y': [3],
      }
      ..['port_directions'] = {
        'A': 'input',
        'B': 'input',
        'Y': 'output',
      };
    expect(evaluator.canEvaluate('top/out'), isTrue);
    _expectValue(
      _evaluate(
        modules,
        'out',
        snapshot: {'top/a': '1', 'top/b': '1'},
      ),
      1,
      1,
    );
  });

  test('resolves exposed constants, transitive arrays, and wire aliases', () {
    final modules = _topModule(
      ports: const {},
      netnames: {
        'constOutput': _signal([1, 2]),
        'array': _signal([3, 4, 5, 6]),
        'array_1_': _signal([5, 6]),
        'source': _signal([7, 8]),
        'alias': _signal([7, 8]),
      },
      cells: {
        'constOutput': _cell(
          type: r'$const',
          connections: const {},
          directions: const {"2'b11": 'output'},
        ),
        'arrayConst': _cell(
          type: r'$const',
          connections: {
            "4'b1101": [3, 4, 5, 6],
          },
          directions: const {"4'b1101": 'output'},
        ),
      },
    );

    _expectValue(
      _evaluate(modules, 'constOutput', snapshot: const {}),
      3,
      2,
    );
    _expectValue(
      _evaluate(modules, 'array_1_', snapshot: const {}),
      3,
      2,
    );
    _expectValue(
      _evaluate(modules, 'alias', snapshot: const {'top/source': "2'b10"}),
      2,
      2,
    );
  });

  test('returns unknown values for cyclic and literal-driven cell inputs', () {
    final modules = _topModule(
      ports: const {},
      netnames: {
        'a': _signal([1]),
        'b': _signal([2]),
        'literalOut': _signal([3]),
      },
      cells: {
        'aDriver': _cell(
          type: r'$buf',
          connections: {
            'A': [2],
            'Y': [1],
          },
          directions: const {'A': 'input', 'Y': 'output'},
        ),
        'bDriver': _cell(
          type: r'$buf',
          connections: {
            'A': [1],
            'Y': [2],
          },
          directions: const {'A': 'input', 'Y': 'output'},
        ),
        'literalDriver': _cell(
          type: r'$and',
          connections: {
            'A': ['1'],
            'B': ['x'],
            'Y': [3],
          },
          directions: const {'A': 'input', 'B': 'input', 'Y': 'output'},
        ),
      },
    );

    expect(
      parseHexToLV(_evaluate(modules, 'a', snapshot: const {}).value, 1),
      LogicValue.filled(1, LogicValue.x),
    );
    expect(
      parseHexToLV(
          _evaluate(modules, 'literalOut', snapshot: const {}).value, 1),
      LogicValue.filled(1, LogicValue.x),
    );
  });

  test('recursively evaluates an untracked child module output', () {
    final modules = {
      ..._topModule(
        ports: {
          'childOut': _signal([1]),
        },
        netnames: {
          'childOut': _signal([1]),
        },
        cells: {
          'child': _cell(
            type: 'Child',
            connections: {
              'O': [1],
            },
            directions: const {'O': 'output'},
          ),
        },
      ),
      'Child': {
        'ports': {
          'O': _signal([10]),
        },
        'netnames': {
          'O': _signal([10]),
        },
        'cells': {
          'constant': _cell(
            type: r'$const',
            connections: {
              "1'b1": [10],
            },
            directions: const {"1'b1": 'output'},
          ),
        },
      },
    };

    _expectValue(
      _evaluate(modules, 'childOut', snapshot: const {}),
      1,
      1,
    );
  });
}
