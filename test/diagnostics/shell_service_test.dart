// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// shell_service_test.dart
// Tests for the typed ROHD design-session shell service.
//
// 2026 August
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:convert';

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

class _ShellLookupModule extends Module {
  _ShellLookupModule(Logic dataIn)
      : super(name: 'shellTop', definitionName: 'ShellLookupTop') {
    dataIn = addInput('dataIn', dataIn);
    addOutput('dataOut') <= ~dataIn;
  }
}

class _ShellLeafModule extends Module {
  _ShellLeafModule(Logic dataIn)
      : super(name: 'leaf', definitionName: 'ShellLeaf') {
    dataIn = addInput('dataIn', dataIn);
    addOutput('dataOut') <= ~dataIn;
  }
}

class _ShellMiddleModule extends Module {
  _ShellMiddleModule(Logic dataIn)
      : super(name: 'middle', definitionName: 'ShellMiddle') {
    dataIn = addInput('dataIn', dataIn);
    final leaf = _ShellLeafModule(dataIn);
    addOutput('dataOut') <= leaf.output('dataOut');
  }
}

class _ShellHierarchyModule extends Module {
  _ShellHierarchyModule(Logic dataIn)
      : super(name: 'hierarchyTop', definitionName: 'ShellHierarchyTop') {
    dataIn = addInput('dataIn', dataIn);
    final middle = _ShellMiddleModule(dataIn);
    addOutput('dataOut') <= middle.output('dataOut');
  }
}

void main() {
  setUp(() {
    ModuleServices.instance.reset();
    WaveformDataService.instance.clear();
  });
  tearDown(() {
    ModuleServices.instance.reset();
    WaveformDataService.instance.clear();
  });

  test(
    'exposes the typed design session through a VM-ready envelope',
    () async {
      final dut = _ShellLookupModule(Logic(name: 'dataIn'));
      await dut.build();
      NetlistService(dut);

      final response = Map<String, Object?>.from(
        jsonDecode(
          await RohdShellService.executeDesignSession(
            RohdDesignSessionProtocol.findSignal,
            jsonEncode({'path': 'shellTop/dataOut'}),
          ),
        ) as Map,
      );
      final signal = Map<String, Object?>.from(response['result']! as Map);
      final definitionNamedResponse = Map<String, Object?>.from(
        jsonDecode(
          await RohdShellService.executeDesignSession(
            RohdDesignSessionProtocol.findSignal,
            jsonEncode({'path': 'ShellLookupTop/dataOut'}),
          ),
        ) as Map,
      );
      final rootlessResponse = Map<String, Object?>.from(
        jsonDecode(
          await RohdShellService.executeDesignSession(
            RohdDesignSessionProtocol.findSignal,
            jsonEncode({'path': 'dataOut'}),
          ),
        ) as Map,
      );
      final definitionNamedPortResponse = Map<String, Object?>.from(
        jsonDecode(
          await RohdShellService.executeDesignSession(
            RohdDesignSessionProtocol.findPort,
            jsonEncode({'path': 'ShellLookupTop/dataIn'}),
          ),
        ) as Map,
      );
      final signals = Map<String, Object?>.from(
        jsonDecode(
          await RohdShellService.executeDesignSession(
            RohdDesignSessionProtocol.findSignals,
            jsonEncode({'pattern': '.*'}),
          ),
        ) as Map,
      );
      final fanin = Map<String, Object?>.from(
        jsonDecode(
          await RohdShellService.executeDesignSession(
            RohdDesignSessionProtocol.fanin,
            jsonEncode({'signal': signal}),
          ),
        ) as Map,
      );

      expect(response['schemaVersion'], 1);
      expect(response['ok'], isTrue);
      expect(definitionNamedResponse['ok'], isTrue);
      expect(rootlessResponse['ok'], isTrue);
      expect(definitionNamedPortResponse['ok'], isTrue);
      expect(signal['address'], isNotEmpty);
      expect(
        (signals['result']! as Map<Object?, Object?>)['items'],
        everyElement({'address': isNotEmpty, 'kind': anyOf('signal', 'port')}),
      );
      expect(fanin['ok'], isTrue);
    },
  );

  test('transparent fanout crosses hierarchical port boundaries', () async {
    final dut = _ShellHierarchyModule(Logic(name: 'dataIn'));
    await dut.build();
    final netlist = NetlistService(dut);
    final root = netlist.hierarchy.root;
    final input = root.signals[root.signalIndexByName('dataIn')];

    final opaque = netlist.fanout(input);
    final transparent = netlist.fanout(input, transparent: true);

    expect(opaque, isNotEmpty);
    expect(transparent, isNotEmpty);
    expect(opaque.first.parent!.children, isNotEmpty);
    expect(
      transparent.every((signal) => signal.parent!.children.isEmpty),
      isTrue,
    );
  });

  test('transparent finds return only leaf occurrence DTOs', () async {
    final dut = _ShellHierarchyModule(Logic(name: 'dataIn'));
    await dut.build();
    NetlistService(dut);

    final cells = Map<String, Object?>.from(
      jsonDecode(
        await RohdShellService.executeDesignSession(
          RohdDesignSessionProtocol.findCells,
          jsonEncode({'pattern': '.*', 'transparent': true}),
        ),
      ) as Map,
    );
    final signals = Map<String, Object?>.from(
      jsonDecode(
        await RohdShellService.executeDesignSession(
          RohdDesignSessionProtocol.findSignals,
          jsonEncode({'pattern': '.*', 'transparent': true}),
        ),
      ) as Map,
    );

    final cellItems = (cells['result']! as Map)['items']! as List;
    final signalItems = (signals['result']! as Map)['items']! as List;
    expect(cellItems, everyElement({'address': isNotEmpty, 'kind': 'cell'}));
    expect(
      signalItems,
      everyElement({'address': isNotEmpty, 'kind': anyOf('signal', 'port')}),
    );
  });

  test('exposes bounded shared hierarchy path completions', () async {
    final dut = _ShellHierarchyModule(Logic(name: 'dataIn'));
    await dut.build();
    NetlistService(dut);

    final response = Map<String, Object?>.from(
      jsonDecode(
        await RohdShellService.executeDesignSession(
          RohdDesignSessionProtocol.completeCellPaths,
          jsonEncode({'prefix': 'hierarchyTop/m', 'limit': 1}),
        ),
      ) as Map,
    );

    expect(response['ok'], isTrue);
    expect((response['result']! as Map)['items'], ['hierarchyTop/middle/']);
  });

  test(
    'owns command help, aliases, and completion by frontend session',
    () async {
      final dut = _ShellLookupModule(Logic(name: 'dataIn'));
      await dut.build();
      NetlistService(dut);

      Map<String, Object?> command(String sessionId, String input) =>
          Map<String, Object?>.from(
            jsonDecode(
              RohdShellService.executeDesignCommandNow(sessionId, input),
            ) as Map,
          );
      Map<String, Object?> completion(String input) =>
          Map<String, Object?>.from(
            jsonDecode(
              RohdShellService.completeDesignCommandNow(
                'terminal',
                input,
                input.length,
              ),
            ) as Map,
          );

      final help = command('terminal', 'help');
      final lookup = command(
        'terminal',
        'let output = find-signal shellTop/dataOut',
      );
      final portLookup = command(
        'terminal',
        'let outputPort = find-port shellTop/dataOut',
      );
      final inputPortLookup = command(
        'terminal',
        'let inputPort = find-port shellTop/dataIn',
      );
      final selection = command(
        'terminal',
        "let selection = find-signals '.*'",
      );
      final ports = command('terminal', "let ports = find-ports '.*'");
      final inspectedOutput = command('terminal', r'$output');
      final inspectedPorts = command('terminal', r'$ports');
      final firstSelection = command('terminal', r'$selection[0]');
      final selectionLength = command('terminal', r'$selection.length');
      final missingSelection = command('terminal', r'$selection[1000]');
      final name = command('terminal', r'name $output');
      final inputPortName = command('terminal', r'name $inputPort');
      final fanin = command('terminal', r'fanin $output');
      final send = command('terminal', r'send $output');
      final sendPort = command('terminal', r'send $outputPort');
      final sendInputPort = command('terminal', r'send $inputPort');
      final candidates = completion('find-signal shellTop/data');
      final definitionCandidates = completion('find-signal S');
      final assignmentCommands = completion('let result = ');
      final assignmentCandidates = completion(
        'let result = find-signal shellTop/data',
      );
      final portCandidates = completion('find-port shellTop/data');
      final otherSession = command('debugger', r'fanin $output');

      expect(help['ok'], isTrue);
      expect(
        help['commands'],
        contains(r'find-signals <hierarchy-regex> [$root] [transparent]'),
      );
      expect(help['commands'], contains('send <signal>'));
      expect(lookup['alias'], 'output');
      expect(portLookup['alias'], 'outputPort');
      expect(inputPortLookup['alias'], 'inputPort');
      expect(selection['alias'], 'selection');
      expect((selection['result']! as Map)['items'], isNotEmpty);
      expect(ports['alias'], 'ports');
      expect((ports['result']! as Map)['items'], isNotEmpty);
      expect(inspectedOutput['result'], {
        'address': isNotEmpty,
        'kind': 'port',
      });
      expect((inspectedPorts['result']! as Map)['items'], isNotEmpty);
      expect(firstSelection['result'], {
        'address': isNotEmpty,
        'kind': anyOf('signal', 'port'),
      });
      final selectionItems =
          (selection['result']! as Map<Object?, Object?>)['items']! as List;
      expect(selectionLength['result'], selectionItems.length);
      expect(missingSelection['ok'], isFalse);
      expect((missingSelection['error']! as Map)['code'], 'invalidArgument');
      expect(name['result'], {
        'address': isNotEmpty,
        'kind': 'port',
        'path': 'shellTop/dataOut',
        'name': 'dataOut',
        'width': 1,
        'direction': 'output',
      });
      expect(inputPortName['result'], {
        'address': isNotEmpty,
        'kind': 'port',
        'path': 'shellTop/dataIn',
        'name': 'dataIn',
        'width': 1,
        'direction': 'input',
      });
      expect(fanin['ok'], isTrue);
      expect(send, {
        'ok': true,
        'result': {
          'paths': ['shellTop/dataOut'],
        },
      });
      expect(sendPort, {
        'ok': true,
        'result': {
          'paths': ['shellTop/dataOut'],
        },
      });
      expect(sendInputPort, {
        'ok': true,
        'result': {
          'paths': ['shellTop/dataIn'],
        },
      });
      expect(candidates, {'ok': true, 'items': contains('shellTop/dataOut')});
      expect(definitionCandidates, {
        'ok': true,
        'items': contains('ShellLookupTop/dataOut'),
      });
      expect(assignmentCommands, {
        'ok': true,
        'items': containsAll([
          'find-cell',
          'find-cells',
          'find-port',
          'find-ports',
          'find-signal',
          'find-signals',
        ]),
      });
      expect(assignmentCandidates, {
        'ok': true,
        'items': contains('shellTop/dataOut'),
      });
      expect(portCandidates, {
        'ok': true,
        'items': contains('shellTop/dataOut'),
      });
      expect(completion('find-ports .* t'), {
        'ok': true,
        'items': contains('transparent'),
      });
      expect(otherSession['ok'], isFalse);
      expect((otherSession['error']! as Map)['code'], 'invalidArgument');
    },
  );

  test(
    'gets the latest or historical waveform value through an alias',
    () async {
      final dut = _ShellLookupModule(Logic(name: 'dataIn'));
      await dut.build();
      NetlistService(dut);
      WaveformDataService.init(dut);
      WaveformDataService.instance
        ..recordChange('shellTop/dataIn', 5, '1')
        ..recordChange('shellTop/dataIn', 10, '0');

      Map<String, Object?> command(String input) => Map<String, Object?>.from(
            jsonDecode(
                    RohdShellService.executeDesignCommandNow('terminal', input))
                as Map,
          );

      final lookup = command('let input = find-signal shellTop/dataIn');
      final latest = command(r'get-value $input');
      final historical = command(r'get-value $input 6');
      final status = command('status');

      expect(lookup['alias'], 'input');
      expect((status['result']! as Map)['capabilities'], contains('waveform'));
      expect(latest['result'], {
        'address': isNotEmpty,
        'kind': 'port',
        'path': 'shellTop/dataIn',
        'width': 1,
        'time': 10,
        'value': '0',
        'sampleTime': 10,
      });
      expect(historical['result'], {
        'address': isNotEmpty,
        'kind': 'port',
        'path': 'shellTop/dataIn',
        'width': 1,
        'time': 6,
        'value': '1',
        'sampleTime': 5,
      });
    },
  );
}
