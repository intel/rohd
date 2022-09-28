/// Copyright (C) 2021 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// bus.dart
/// Definition for modules related to bus operations
///
/// 2021 August 2
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:rohd/rohd.dart';

/// A [Module] which gives access to a subset range of signals of the input.
///
/// The returned signal is inclusive of both the [startIndex] and [endIndex].
/// The output [subset] will have width equal to `|endIndex - startIndex| + 1`.
class BusSubset extends Module with InlineSystemVerilog {
  /// Name for a port of this module.
  late final String _original, _subset;

  /// The input to get a subset of.
  Logic get original => input(_original);

  /// The output, a subset of [original].
  Logic get subset => output(_subset);

  /// Index of the subset.
  final int startIndex, endIndex;

  BusSubset(Logic bus, this.startIndex, this.endIndex,
      {String name = 'bussubset'})
      : super(name: name) {
    if (startIndex < 0 || endIndex < 0) {
      throw Exception('Cannot access negative indices!'
          '  Indices $startIndex and/or $endIndex are invalid.');
    }
    if (endIndex > bus.width - 1 || startIndex > bus.width - 1) {
      throw Exception(
          'Index out of bounds, indices $startIndex and $endIndex must be less than width-1');
    }

    // original name can't be unpreferred because you cannot do a bit slice on expressions
    // in SystemVerilog, and other expressions could have been in-lined
    _original = 'original_' + bus.name;

    _subset =
        Module.unpreferredName('subset_${endIndex}_${startIndex}_' + bus.name);

    addInput(_original, bus, width: bus.width);
    var newWidth = (endIndex - startIndex).abs() + 1;
    addOutput(_subset, width: newWidth);
    subset
        .makeUnassignable(); // so that people can't do a slice assign, not (yet?) implemented

    _setup();
  }

  /// Performs setup steps for custom functional behavior.
  void _setup() {
    _execute(); // for initial values
    original.glitch.listen((args) {
      _execute();
    });
  }

  /// Executes the functional behavior of this gate.
  void _execute() {
    if (endIndex < startIndex) {
      subset.put(original.value.getRange(endIndex, startIndex + 1).reversed);
    } else {
      subset.put(original.value.getRange(startIndex, endIndex + 1));
    }
  }

  @override
  String inlineVerilog(Map<String, String> inputs) {
    if (inputs.length != 1) {
      throw Exception('BusSubset has exactly one input, but saw $inputs.');
    }
    var a = inputs[_original]!;

    // SystemVerilog doesn't allow reverse-order select to reverse a bus, so do it manually
    if (startIndex > endIndex) {
      return '{' +
          List.generate(startIndex - endIndex + 1, (i) => '$a[${endIndex + i}]')
              .join(',') +
          '}';
    }

    var sliceString =
        startIndex == endIndex ? '[$startIndex]' : '[$endIndex:$startIndex]';
    return '$a$sliceString';
  }
}

/// A [Module] that performs concatenation of signals into one bigger [Logic].
///
/// The concatenation occurs such that index 0 of [signals] is the *most* significant bit(s).
///
/// You can use convenience functions [swizzle()] or [rswizzle()] to more easily use this [Module].
class Swizzle extends Module with InlineSystemVerilog {
  final String _out = Module.unpreferredName('swizzled');

  /// The output port containing concatenated signals.
  Logic get out => output(_out);

  final List<Logic> _swizzleInputs = [];

  Swizzle(List<Logic> signals, {String name = 'swizzle'}) : super(name: name) {
    var idx = 0;
    var outputWidth = 0;
    for (var signal in signals.reversed) {
      //reverse so bit 0 is the last thing in the input list
      var inputName = Module.unpreferredName('in${idx++}');
      addInput(inputName, signal, width: signal.width);
      _swizzleInputs.add(input(inputName));
      outputWidth += signal.width;
    }
    addOutput(_out, width: outputWidth);

    _execute(); // for initial values
    for (var swizzleInput in _swizzleInputs) {
      swizzleInput.glitch.listen((args) {
        _execute();
      });
    }
  }

  /// Executes the functional behavior of this gate.
  void _execute() {
    var updatedVal =
        _swizzleInputs.reversed.map((e) => e.value).toList().swizzle();
    out.put(updatedVal);
  }

  @override
  String inlineVerilog(Map<String, String> inputs) {
    if (inputs.length != _swizzleInputs.length) {
      throw Exception('This swizzle has ${_swizzleInputs.length} inputs,'
          ' but saw $inputs with ${inputs.length} values.');
    }
    var inputStr = _swizzleInputs.reversed
        .where((e) => e.width > 0)
        .map((e) => inputs[e.name])
        .join(',');
    return '{$inputStr}';
  }
}
