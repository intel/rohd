import 'dart:convert';
import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

class SimpleModule extends Module {
  SimpleModule(Logic a) : super(name: 'SimpleTest') {
    a = addInput('a', a, width: 8);
    final b = addOutput('b', width: 8);
    b <= ~a;
    addOutput('unused_port', width: 4); // not connected internally
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
    ModuleServices.instance.reset();
  });

  test('slim ports carry connected attribute', () async {
    final a = Logic(width: 8, name: 'a');
    final mod = SimpleModule(a);
    await mod.build();
    final netSvc = await NetlistService.create(mod);

    final slim = netSvc.slimJson;

    final parsed = json.decode(slim) as Map<String, dynamic>;
    final netlist = parsed['netlist'] as Map<String, dynamic>;
    final modules = netlist['modules'] as Map<String, dynamic>;

    // Find the SimpleTest module
    // ignore: avoid_print
    print('Module keys: ${modules.keys.toList()}');
    // The module name may be the type name or uniquified; find it
    final simpleTestKey = modules.keys.firstWhere(
      (k) => k.contains('SimpleTest'),
      orElse: () => modules.keys.first,
    );
    final simpleTest = modules[simpleTestKey] as Map<String, dynamic>;
    // ignore: avoid_print
    print('Using module: $simpleTestKey');

    final ports = simpleTest['ports'] as Map<String, dynamic>;

    // Port 'a' is connected internally (feeds ~a)
    final portA = ports['a'] as Map<String, dynamic>;
    expect(
      portA['connected'],
      isTrue,
      reason: 'Port a should be marked connected',
    );

    // Port 'b' is connected internally (output of ~a)
    final portB = ports['b'] as Map<String, dynamic>;
    expect(
      portB['connected'],
      isTrue,
      reason: 'Port b should be marked connected',
    );

    // Port 'unused_port' is NOT connected internally
    final portUnused = ports['unused_port'] as Map<String, dynamic>;
    expect(
      portUnused.containsKey('connected'),
      isFalse,
      reason: 'unused_port should not have connected attribute',
    );

    // Print for visibility
    for (final p in ports.entries) {
      final pd = p.value as Map<String, dynamic>;
      // ignore: avoid_print
      print('Port ${p.key}: connected=${pd["connected"]}');
    }
  });
}
