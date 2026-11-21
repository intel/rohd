// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// netlist_yosys_test.dart
// Direct JSON and SystemVerilog equivalence using design-specific techmaps.
//
// 2026 November 20
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

class _Pair extends LogicStructure {
  _Pair({super.name})
      : super([Logic(name: 'low', width: 4), Logic(name: 'high', width: 4)]);

  Logic get low => elements[0];
  Logic get high => elements[1];

  @override
  _Pair clone({String? name}) => _Pair(name: name);
}

class _StructProbe extends Module {
  _StructProbe(_Pair external) : super(definitionName: 'StructProbe') {
    final input = addTypedInput('inputPair', external);
    final result = addTypedOutput('result', _Pair.new);
    result.low <= ~input.high;
    result.high <= input.low;
  }
}

const _pairTechmap = r'''
(* techmap_celltype = "$struct_unpack" *)
module unpack_pair #(
  parameter STRUCT_NAME = "", FIELD_COUNT = 2,
  parameter FIELD_0_NAME = "", FIELD_0_OFFSET = 0, FIELD_0_WIDTH = 4,
  parameter FIELD_1_NAME = "", FIELD_1_OFFSET = 4, FIELD_1_WIDTH = 4
)(input [7:0] A, output [3:0] low, output [3:0] high);
  assign low = A[FIELD_0_OFFSET +: FIELD_0_WIDTH];
  assign high = A[FIELD_1_OFFSET +: FIELD_1_WIDTH];
endmodule

(* techmap_celltype = "$struct_pack" *)
module pack_pair #(
  parameter STRUCT_NAME = "", FIELD_COUNT = 2,
  parameter FIELD_0_NAME = "", FIELD_0_OFFSET = 0, FIELD_0_WIDTH = 4,
  parameter FIELD_1_NAME = "", FIELD_1_OFFSET = 4, FIELD_1_WIDTH = 4
)(input [3:0] low, input [3:0] high, output [7:0] Y);
  assign Y[FIELD_0_OFFSET +: FIELD_0_WIDTH] = low;
  assign Y[FIELD_1_OFFSET +: FIELD_1_WIDTH] = high;
endmodule
''';

bool _yosysAvailable(String executable) {
  try {
    return Process.runSync(executable, ['-V']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

void main() {
  final configuredYosys = Platform.environment['ROHD_YOSYS'];
  final yosys = configuredYosys ?? 'yosys';
  final available = _yosysAvailable(yosys);

  test('Yosys compares direct ROHD JSON against SystemVerilog', () async {
    final top = _StructProbe(_Pair());
    await top.build();
    final directory = await Directory.systemTemp.createTemp('rohd_yosys_');
    addTearDown(() async {
      await directory.delete(recursive: true);
      await Simulator.reset();
    });

    final json = NetlistSynthesizer(
      configuration:
          const NetlistSynthesizerConfiguration(omitRohdMetadata: true),
    ).synthesizeToJson(top);
    final modules = (jsonDecode(json) as Map<String, dynamic>)['modules']
        as Map<String, dynamic>;
    final definition = modules[top.definitionName] as Map<String, dynamic>;
    final cells = definition['cells'] as Map<String, dynamic>;
    expect(
      cells.values.map((cell) => (cell as Map<String, dynamic>)['type']),
      containsAll([r'$struct_unpack', r'$struct_pack', r'$not']),
    );
    final netlist = File('${directory.path}/design with spaces.json');
    final systemVerilog = File('${directory.path}/design.sv');
    await netlist.writeAsString(json);
    await systemVerilog
        .writeAsString(SystemVerilogService(top, register: false).output);
    final map = File('${directory.path}/pair_map.v');
    await map.writeAsString(_pairTechmap);
    Future<ProcessResult> runMiter() =>
        Process.run(Platform.resolvedExecutable, [
          File('tool/yosys_netlist_miter.dart').absolute.path,
          netlist.path,
          systemVerilog.path,
          top.definitionName,
          map.path,
        ], environment: {
          'ROHD_YOSYS': yosys
        });
    final result = await runMiter();
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout,
        contains('SAT proof finished - no model found: SUCCESS'));

    await map.writeAsString(_pairTechmap.replaceFirst(
      'A[FIELD_0_OFFSET +: FIELD_0_WIDTH]',
      'A[FIELD_1_OFFSET +: FIELD_1_WIDTH]',
    ));
    final wrongMapping = await runMiter();
    expect(wrongMapping.exitCode, isNot(0),
        reason: 'A wrong struct bit mapping must fail equivalence.');
    expect('${wrongMapping.stdout}\n${wrongMapping.stderr}',
        contains('proof did fail'));

    await map.writeAsString(_pairTechmap);
    await systemVerilog.writeAsString('''
module StructProbe(input [7:0] inputPair, output [6:0] result);
  assign result = inputPair[6:0];
endmodule
''');
    final wrongInterface = await runMiter();
    expect(wrongInterface.exitCode, isNot(0),
        reason: 'Different output widths must not pass the miter.');
  },
      skip: available || configuredYosys != null
          ? false
          : 'Yosys executable not available');
}
