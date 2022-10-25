import 'package:rohd/rohd.dart';
import 'package:test/test.dart';
import 'dart:io';

class LogicTestModule extends Module {
  LogicTestModule(Logic a) {
    addInput(a.name, a, width: a.width);
  }
}

void main() {
  test(
      'GIVEN logic name is valid '
      'THEN expected to see proper name being generated', () async {
    final bus = Logic(name: 'validName');
    final mod = LogicTestModule(bus);
    await mod.build();
    final sv = mod.generateSynth();
    expect(sv, contains('input logic validName'));
  });

  test('GIVEN logic name is invalid THEN expected to see sanitized name',
      () async {
    final bus = Logic(name: '&*-FinvalidN11Me');
    final mod = LogicTestModule(bus);
    await mod.build();
    final sv = mod.generateSynth();
    expect(sv, contains('___FinvalidN11Me'));
  });

  test('GIVEN logic name is null THEN expected to see autogeneration of name',
      () async {
    final bus = Logic();
    final mod = LogicTestModule(bus);
    await mod.build();
    final sv = mod.generateSynth();
    expect(sv, contains('input logic s0'));
  });
}
