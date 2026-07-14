// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// generate.dart
// Definition for SystemVerilog generate block constructs.
//
// 2026 June
// Author: Joel Kimmel

import 'package:rohd/rohd.dart';

/// Represents a SystemVerilog `generate if` block.
///
/// In simulation, [conditionValue] is evaluated at construction time to
/// determine which branch's hardware is active. In generated SystemVerilog,
/// both branches appear wrapped in a `generate if (...) begin ... end`
/// block.
///
/// The condition is a compile-time (elaboration-time) condition, typically
/// based on a [ModuleParameter]. For runtime conditions, use [If] inside
/// a [Combinational] or [Sequential] block instead.
///
/// Both the `then` and optional `else` bodies must be [Module]s with
/// matching input/output port names and widths, since they drive the same
/// signals.
///
/// The body builders receive [GenerateIf]'s internal input ports so that
/// sub-modules are properly scoped within the generate block.
///
/// Example:
/// ```dart
/// class MyTop extends Module {
///   MyTop(Logic a, Logic b, {int width = 8}) : super(name: 'top') {
///     a = addInput('a', a, width: width);
///     b = addInput('b', b, width: width);
///     addOutput('result', width: width);
///
///     final widthParam = ModuleParameter<int>('WIDTH', defaultValue: width);
///     addModuleParameter(widthParam);
///
///     final genIf = GenerateIf(
///       conditionExpression: '${widthParam.name} > 4',
///       conditionValue: widthParam.defaultValue > 4,
///       inputs: {'a': a, 'b': b},
///       outputWidths: {'sum': width},
///       thenBody: (inputs) =>
///           WideAdder(inputs['a']!, inputs['b']!, width: width),
///       elseBody: (inputs) =>
///           NarrowAdder(inputs['a']!, inputs['b']!, width: width),
///     );
///
///     output('result') <= genIf.output('sum');
///   }
/// }
/// ```
class GenerateIf extends Module with SystemVerilog {
  /// The SystemVerilog expression for the generate condition.
  final String conditionExpression;

  /// The concrete boolean value of the condition for simulation.
  final bool conditionValue;

  /// The SV label for the `then` branch (e.g., `gen_then`).
  final String thenLabel;

  /// The SV label for the `else` branch (e.g., `gen_else`).
  final String elseLabel;

  /// The sub-module for the `then` branch.
  late final Module _thenModule;

  /// The sub-module for the `else` branch, if provided.
  late final Module? _elseModule;

  /// The module that is active during simulation (based on [conditionValue]).
  Module get activeModule =>
      conditionValue ? _thenModule : (_elseModule ?? _thenModule);

  /// Creates a [GenerateIf] block.
  ///
  /// [conditionExpression] is the SV expression (e.g., `'WIDTH > 4'`).
  ///
  /// [conditionValue] is the concrete Dart boolean for simulation.
  ///
  /// [inputs] maps port names to source signals from the parent module.
  /// These will become input ports on this [GenerateIf].
  ///
  /// [outputWidths] declares the output port names and widths that the
  /// body modules must produce.
  ///
  /// [thenBody] builds the [Module] for the `then` branch. It receives
  /// a map of input port signals to connect to.
  ///
  /// [elseBody] optionally builds the [Module] for the `else` branch.
  ///
  /// Both body modules must have outputs matching [outputWidths].
  GenerateIf({
    required this.conditionExpression,
    required this.conditionValue,
    required Map<String, Logic> inputs,
    required Map<String, int> outputWidths,
    required Module Function(Map<String, Logic> inputs) thenBody,
    Module Function(Map<String, Logic> inputs)? elseBody,
    this.thenLabel = 'gen_then',
    this.elseLabel = 'gen_else',
    super.name = 'generate_if',
  }) {
    // Create input ports on this GenerateIf.
    final internalInputs = <String, Logic>{};
    for (final entry in inputs.entries) {
      internalInputs[entry.key] =
          addInput(entry.key, entry.value, width: entry.value.width);
    }

    // Create output ports.
    for (final entry in outputWidths.entries) {
      addOutput(entry.key, width: entry.value);
    }

    // Build both branches, passing our internal ports.
    _thenModule = thenBody(internalInputs);
    _elseModule = elseBody?.call(internalInputs);

    // Validate port matching if both branches exist.
    if (_elseModule != null) {
      _validatePortsMatch(_thenModule, _elseModule!);
    }

    // Wire the active branch's outputs to our outputs.
    for (final outputName in outputWidths.keys) {
      output(outputName) <= activeModule.outputs[outputName]!;
    }
  }

  /// Validates that two modules have the same port names and widths.
  static void _validatePortsMatch(Module a, Module b) {
    for (final inputName in a.inputs.keys) {
      if (!b.inputs.containsKey(inputName)) {
        throw IllegalConfigurationException(
            'GenerateIf: else branch is missing input "$inputName" '
            'that exists in then branch.');
      }
      if (a.inputs[inputName]!.width != b.inputs[inputName]!.width) {
        throw IllegalConfigurationException(
            'GenerateIf: input "$inputName" width mismatch between branches: '
            '${a.inputs[inputName]!.width} vs ${b.inputs[inputName]!.width}.');
      }
    }
    for (final inputName in b.inputs.keys) {
      if (!a.inputs.containsKey(inputName)) {
        throw IllegalConfigurationException(
            'GenerateIf: then branch is missing input "$inputName" '
            'that exists in else branch.');
      }
    }

    for (final outputName in a.outputs.keys) {
      if (!b.outputs.containsKey(outputName)) {
        throw IllegalConfigurationException(
            'GenerateIf: else branch is missing output "$outputName" '
            'that exists in then branch.');
      }
      if (a.outputs[outputName]!.width != b.outputs[outputName]!.width) {
        throw IllegalConfigurationException(
            'GenerateIf: output "$outputName" width mismatch: '
            '${a.outputs[outputName]!.width} vs '
            '${b.outputs[outputName]!.width}.');
      }
    }
    for (final outputName in b.outputs.keys) {
      if (!a.outputs.containsKey(outputName)) {
        throw IllegalConfigurationException(
            'GenerateIf: then branch is missing output "$outputName" '
            'that exists in else branch.');
      }
    }
  }

  @override
  String instantiationVerilog(
    String instanceType,
    String instanceName,
    Map<String, String> ports,
  ) {
    final buf = StringBuffer()
      ..writeln('//  $instanceName')
      ..writeln('generate')
      ..writeln('  if ($conditionExpression) begin : $thenLabel')
      ..writeln('    ${_instantiationForBranch(_thenModule, ports)}');

    if (_elseModule != null) {
      buf
        ..writeln('  end else begin : $elseLabel')
        ..writeln('    ${_instantiationForBranch(_elseModule!, ports)}');
    }

    buf
      ..writeln('  end')
      ..writeln('endgenerate');

    return buf.toString();
  }

  /// Generates a sub-module instantiation line for a branch module,
  /// mapping our ports to the branch module's ports.
  String _instantiationForBranch(
      Module branchModule, Map<String, String> outerPorts) {
    final branchPorts = <String, String>{};

    for (final inputName in branchModule.inputs.keys) {
      if (outerPorts.containsKey(inputName)) {
        branchPorts[inputName] = outerPorts[inputName]!;
      }
    }

    for (final outputName in branchModule.outputs.keys) {
      if (outerPorts.containsKey(outputName)) {
        branchPorts[outputName] = outerPorts[outputName]!;
      }
    }

    return SystemVerilogSynthesizer.instantiationVerilogFor(
      module: branchModule,
      instanceType: branchModule.definitionName,
      instanceName: '${branchModule.name}_inst',
      ports: branchPorts,
      forceStandardInstantiation: true,
    );
  }
}

/// Represents a SystemVerilog `generate for` block.
///
/// In simulation, the loop is unrolled at construction time — each iteration
/// calls `bodyBuilder` with the concrete index value to create real hardware.
/// In generated SystemVerilog, the iterations are wrapped in a
/// `generate for (genvar ...) begin ... end endgenerate` block.
///
/// This is useful for creating parameterized, repetitive hardware structures
/// where the iteration count depends on a [ModuleParameter].
///
/// The `bodyBuilder` must produce modules with the same port names and widths
/// for every iteration.
///
/// Each output declared in `outputWidths` is exposed as a single bus of width
/// `count * perIterationWidth`. In the generated SV, the sub-module's output
/// port is connected using genvar indexing (e.g., `.out(out[i])` for 1-bit
/// outputs or `.out(out[i*W +: W])` for multi-bit outputs).
///
/// Example:
/// ```dart
/// class MyTop extends Module {
///   MyTop(Logic inp, {int count = 4}) : super(name: 'top') {
///     inp = addInput('inp', inp);
///     final countParam = ModuleParameter<int>('N', defaultValue: count);
///     addModuleParameter(countParam);
///
///     final genFor = GenerateFor(
///       count: count,
///       countExpression: countParam.name,
///       inputs: {'inp': inp},
///       outputWidths: {'out': 1},
///       bodyBuilder: (i, inputs) => Inverter(inputs['inp']!),
///     );
///
///     addOutput('out', width: count,
///         widthExpression: countParam.toExpression());
///     output('out') <= genFor.output('out');
///   }
/// }
/// ```
class GenerateFor extends Module with SystemVerilog {
  /// The concrete number of iterations for simulation.
  final int count;

  /// The SV expression for the upper bound of the loop
  /// (e.g., `'N'` or `'WIDTH'`).
  final String countExpression;

  /// The name of the genvar variable (e.g., `'i'`).
  final String genvarName;

  /// The SV label for the generate block.
  final String blockLabel;

  /// The per-iteration output widths, used for genvar index expressions.
  final Map<String, int> _outputWidths;

  /// The sub-modules for each iteration, built at construction time.
  late final List<Module> _iterationModules;

  /// Creates a [GenerateFor] block.
  ///
  /// [count] is the concrete iteration count for simulation.
  ///
  /// [countExpression] is the SV expression for the loop upper bound
  /// (e.g., a parameter name like `'N'`).
  ///
  /// [inputs] maps port names to source signals from the parent module.
  ///
  /// [outputWidths] declares the per-iteration output port widths.
  /// Each output is exposed as a single bus of width
  /// `count * perIterationWidth`.
  ///
  /// [genvarName] is the name of the genvar variable (default: `'i'`).
  ///
  /// [bodyBuilder] creates a [Module] for each iteration, receiving the
  /// loop index and a map of input ports. All iterations must produce
  /// modules with outputs matching [outputWidths].
  GenerateFor({
    required this.count,
    required this.countExpression,
    required Map<String, Logic> inputs,
    required Map<String, int> outputWidths,
    required Module Function(int index, Map<String, Logic> inputs) bodyBuilder,
    this.genvarName = 'i',
    String? blockLabel,
    super.name = 'generate_for',
  })  : _outputWidths = outputWidths,
        blockLabel = blockLabel ?? 'gen_for_block' {
    if (count < 1) {
      throw IllegalConfigurationException(
          'GenerateFor: count must be >= 1, but got $count.');
    }

    // Create input ports on this GenerateFor.
    final internalInputs = <String, Logic>{};
    for (final entry in inputs.entries) {
      internalInputs[entry.key] =
          addInput(entry.key, entry.value, width: entry.value.width);
    }

    // Create bus output ports (width = count * perIterationWidth).
    for (final entry in outputWidths.entries) {
      addOutput(entry.key, width: count * entry.value);
    }

    // Build all iterations for simulation, passing our internal inputs.
    _iterationModules = List.generate(
        count, (i) => bodyBuilder(i, internalInputs),
        growable: false);

    // Validate all iterations match.
    for (var i = 1; i < _iterationModules.length; i++) {
      _validatePortsMatch(_iterationModules.first, _iterationModules[i], i);
    }

    // Wire each iteration's outputs into the bus output via rswizzle.
    for (final outputName in outputWidths.keys) {
      final bits = <Logic>[
        for (var i = 0; i < count; i++)
          _iterationModules[i].outputs[outputName]!,
      ];
      output(outputName) <= bits.rswizzle();
    }
  }

  /// Validates that iteration [index] has matching ports to the first.
  static void _validatePortsMatch(Module first, Module other, int index) {
    for (final inputName in first.inputs.keys) {
      if (!other.inputs.containsKey(inputName)) {
        throw IllegalConfigurationException(
            'GenerateFor: iteration $index is missing input "$inputName" '
            'that exists in iteration 0.');
      }
      if (first.inputs[inputName]!.width != other.inputs[inputName]!.width) {
        throw IllegalConfigurationException(
            'GenerateFor: input "$inputName" width mismatch between '
            'iteration 0 and $index.');
      }
    }

    for (final outputName in first.outputs.keys) {
      if (!other.outputs.containsKey(outputName)) {
        throw IllegalConfigurationException(
            'GenerateFor: iteration $index is missing output "$outputName" '
            'that exists in iteration 0.');
      }
      if (first.outputs[outputName]!.width !=
          other.outputs[outputName]!.width) {
        throw IllegalConfigurationException(
            'GenerateFor: output "$outputName" width mismatch between '
            'iteration 0 and $index.');
      }
    }
  }

  @override
  String instantiationVerilog(
    String instanceType,
    String instanceName,
    Map<String, String> ports,
  ) {
    // Use the first iteration module as the template for the generate body.
    final templateModule = _iterationModules.first;

    final buf = StringBuffer()
      ..writeln('//  $instanceName')
      ..writeln('genvar $genvarName;')
      ..writeln('generate')
      ..writeln('  for ($genvarName = 0; '
          '$genvarName < $countExpression; '
          '$genvarName = $genvarName + 1) begin : $blockLabel');

    // Build the port mapping for the template module.
    final branchPorts = <String, String>{};
    for (final inputName in templateModule.inputs.keys) {
      if (ports.containsKey(inputName)) {
        branchPorts[inputName] = ports[inputName]!;
      }
    }

    // For outputs, use genvar-indexed expressions.
    for (final outputName in templateModule.outputs.keys) {
      final outerName = ports[outputName];
      if (outerName != null) {
        final w = _outputWidths[outputName] ?? 1;
        if (w == 1) {
          branchPorts[outputName] = '$outerName[$genvarName]';
        } else {
          branchPorts[outputName] = '$outerName[$genvarName * $w +: $w]';
        }
      }
    }

    buf
      ..writeln('    ${SystemVerilogSynthesizer.instantiationVerilogFor(
        module: templateModule,
        instanceType: templateModule.definitionName,
        instanceName: '${templateModule.name}_inst',
        ports: branchPorts,
        forceStandardInstantiation: true,
      )}')
      ..writeln('  end')
      ..writeln('endgenerate');

    return buf.toString();
  }
}
