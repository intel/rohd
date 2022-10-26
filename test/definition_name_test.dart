import 'package:rohd/rohd.dart';
import 'package:rohd/src/exceptions/name_exception.dart';
import 'package:rohd/src/utilities/sanitizer.dart';
import 'package:test/test.dart';

class DefinitionName {
  String? name;
  bool isReserved;

  DefinitionName({required this.name, required this.isReserved});

  static String getValidName() => 'specialName';
  static String getInvalidName() => '/--**definitionName+';
}

class ValidDefNameModule extends Module {
  ValidDefNameModule(Logic a, DefinitionName defName)
      : super(
          name: 'specialNameInstance',
          reserveName: false,
          definitionName: defName.name,
          reserveDefinitionName: defName.isReserved,
        ) {
    addInput('a', a, width: a.width);
  }
}

class RunTimeNameModule extends ValidDefNameModule {
  String mockRunTimeString;

  RunTimeNameModule(super.a, super.defName, this.mockRunTimeString);
  @override
  String get definitionName {
    const String? mockDefinitionName = null;

    return Sanitizer.sanitizeSV(mockDefinitionName ?? mockRunTimeString);
  }
}

void main() {
  group('GIVEN that Reserved Definition Name is TRUE,', () {
    test('WHEN definition name is valid, THEN expect to compile successfully.',
        () async {
      final defName =
          DefinitionName(name: DefinitionName.getValidName(), isReserved: true);
      final mod = ValidDefNameModule(Logic(), defName);
      await mod.build();
      final sv = mod.generateSynth();
      // Then it should return compile successfully
      expect(sv, contains('module specialName('));
    });
    test('WHEN definition name is invalid, THEN expect to throw exception.',
        () async {
      final defName = DefinitionName(
          name: DefinitionName.getInvalidName(), isReserved: true);
      final mod = ValidDefNameModule(Logic(), defName);
      await mod.build();
      mod.generateSynth;

      expect(mod.generateSynth,
          throwsA((dynamic e) => e is InvalidReservedNameException));
    });
    test('WHEN definition name is null, THEN expect to throw exception.',
        () async {
      final defName = DefinitionName(name: null, isReserved: true);
      final mod = ValidDefNameModule(Logic(), defName);
      await mod.build();
      expect(mod.generateSynth,
          throwsA((dynamic e) => e is NullReservedNameException));
    });
  });

  group('GIVEN that Reserved Definition Name is FALSE,', () {
    test(
        'WHEN definition name is valid, THEN expected to compile successfully.',
        () async {
      final defName = DefinitionName(
          name: DefinitionName.getValidName(), isReserved: false);
      final mod = ValidDefNameModule(Logic(), defName);
      await mod.build();
      final sv = mod.generateSynth();
      // Then it should return compile successfully
      expect(sv, contains('module specialName('));
    });
    test('WHEN definition name is invalid, THEN expected to sanitize name.',
        () async {
      final defName = DefinitionName(
          name: DefinitionName.getInvalidName(), isReserved: false);
      final mod = ValidDefNameModule(Logic(), defName);
      await mod.build();
      final sv = mod.generateSynth();
      expect(sv, contains('_____definitionName_'));
    });
    group('WHEN definition name is null,', () {
      test('THEN expected to auto initialize name.', () async {
        final defName = DefinitionName(name: null, isReserved: false);
        final mod = ValidDefNameModule(Logic(), defName);
        await mod.build();
        final sv = mod.generateSynth();
        expect(sv, contains('module ValidDefNameModule('));
      });
      test('AND runtimetype name is valid, THEN expect to run successfully',
          () async {
        final defName = DefinitionName(name: null, isReserved: false);
        final mod = RunTimeNameModule(Logic(), defName, 'ValidDefNameModule');
        await mod.build();
        final sv = mod.generateSynth();
        expect(sv, contains('module ValidDefNameModule('));
      });
      test(
          'AND runtime type name is invalid, '
          'THEN expect to sanitize the result', () async {
        final defName = DefinitionName(name: null, isReserved: false);
        final mod = RunTimeNameModule(Logic(), defName, 'bd1gdvua&&%#";;');
        await mod.build();
        final sv = mod.generateSynth();
        expect(sv, contains('module bd1gdvua_______('));
      });
    });
  });
}
