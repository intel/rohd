// Copyright (C) 2021-2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// bus.dart
// Definition for modules related to bus operations
//
// 2021 August 2
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';

/// A [Module] which gives access to a subset range of signals of the input.
///
/// The returned signal is inclusive of both the [startIndex] and [endIndex].
/// The output [subset] will have width equal to `|endIndex - startIndex| + 1`.
///
/// This module also supports nets, allowing subsets to be bidirectional.
class BusSubset extends Module with InlineSystemVerilog {
  /// Name for the input port of this module.
  late final String _originalName;

  /// Name for the output port of this module.
  late final String _subsetName;

  /// The input to get a subset of.
  ///
  /// This is the [input] or [inOut] of this module, and thus should not be
  /// directly connected to outside of this module.
  late final Logic original;

  /// The output, a subset of [original].
  late final Logic subset;

  /// Start index of the subset.
  final int startIndex;

  /// End index of the subset.
  final int endIndex;

  /// Indicates whether this operates bidirectionally on nets.
  final bool _isNet;

  @override
  String get resultSignalName => _subsetName;

  @override
  List<String> get expressionlessInputs => [_originalName];

  /// Constructs a [Module] that accesses a subset from [bus] which ranges
  /// from [startIndex] to [endIndex] (inclusive of both).
  ///
  /// When, [bus] has a width of '1', [startIndex] and [endIndex] are ignored
  /// in the generated SystemVerilog.
  BusSubset(Logic bus, this.startIndex, this.endIndex,
      {super.name = 'bussubset'})
      : _isNet = bus.isNet {
    // If a converted index value is still -ve then it's an Index out of bounds
    // on a Logic Bus
    if (startIndex < 0 || endIndex < 0) {
      throw Exception(
          'Start ($startIndex) and End ($endIndex) must be greater than or '
          'equal to 0.');
    }
    // If the +ve indices are more than Logic bus width, Index out of bounds
    if (endIndex > bus.width - 1 || startIndex > bus.width - 1) {
      throw Exception(
          'Index out of bounds, indices $startIndex and $endIndex must be less'
          ' than ${bus.width}');
    }

    _originalName = Naming.unpreferredName('original_${bus.name}');
    _subsetName =
        Naming.unpreferredName('subset_${endIndex}_${startIndex}_${bus.name}');

    final newWidth = (endIndex - startIndex).abs() + 1;

    if (_isNet) {
      original = addInOut(_originalName, bus, width: bus.width);
      subset =
          LogicNet(width: newWidth, name: _subsetName, naming: Naming.unnamed);
      final internalSubset = addInOut(_subsetName, subset, width: newWidth);

      if (startIndex > endIndex) {
        // reverse case
        for (var i = 0; i < newWidth; i++) {
          internalSubset.quietlyMergeSubsetTo(
            original[startIndex - i] as LogicNet,
            start: endIndex + i,
          );
        }
      } else {
        // normal case
        (original as LogicNet).quietlyMergeSubsetTo(
          internalSubset,
          start: startIndex,
        );
      }
    } else {
      original = addInput(_originalName, bus, width: bus.width);
      subset = addOutput(_subsetName, width: newWidth);

      // so that people can't do a slice assign, not (yet?) implemented
      subset.makeUnassignable(
          reason:
              'The output of a (non-LogicNet) BusSubset ($this) is read-only.');

      _setup();
    }
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
    if (original.width == 1) {
      subset.put(original.value);
      return;
    }

    if (endIndex < startIndex) {
      subset.put(original.value.getRange(endIndex, startIndex + 1).reversed);
    } else {
      subset.put(original.value.getRange(startIndex, endIndex + 1));
    }
  }

  /// A regular expression that will have matches if an expression is included.
  static final RegExp _expressionRegex = RegExp("[()']");

  @override
  String inlineVerilog(Map<String, String> inputs) {
    assert(inputs.length == 1 || (inputs.length == 2 && _isNet),
        'BusSubset has exactly one input, but saw $inputs.');

    final a = inputs[_originalName]!;

    assert(!a.contains(_expressionRegex),
        'Inputs to bus swizzle cannot contain any expressions.');

    // When, input width is 1, ignore startIndex and endIndex
    if (original.width == 1) {
      return a;
    }

    // SystemVerilog doesn't allow reverse-order select to reverse a bus,
    // so do it manually
    if (startIndex > endIndex) {
      final swizzleContents =
          List.generate(startIndex - endIndex + 1, (i) => '$a[${endIndex + i}]')
              .join(',');
      return '{$swizzleContents}';
    }

    final sliceString =
        startIndex == endIndex ? '[$startIndex]' : '[$endIndex:$startIndex]';
    return '$a$sliceString';
  }
}

/// A [Module] that performs concatenation of signals into one bigger [Logic].
///
/// The concatenation occurs such that index 0 of `signals` is the *most*
/// significant bit(s).
///
/// You can use convenience functions from [LogicSwizzle] to more easily use
/// this [Module].
///
/// This module supports nets, allowing concatenation to be bidirectionally
/// driven.
class Swizzle extends Module with InlineSystemVerilog {
  final String _out = Naming.unpreferredName('swizzled');

  /// The output port containing concatenated signals.
  late final Logic out;

  final List<Logic> _swizzleInputs = [];

  /// Whether this [Swizzle] is for [LogicNet]s.
  final bool _isNet;

  /// Constructs a [Module] which concatenates [signals] into one large [out].
  Swizzle(List<Logic> signals, {super.name = 'swizzle'})
      : _isNet = signals.any((e) => e.isNet) {
    var outputWidth = 0;

    final inputCreator = _isNet ? addInOut : addInput;

    var idx = 0;
    for (final signal in signals.reversed) {
      //reverse so bit 0 is the last thing in the input list
      final inputName = Naming.unpreferredName('in${idx++}');
      _swizzleInputs.add(
        inputCreator(inputName, signal, width: signal.width),
      );
      outputWidth += signal.width;
    }

    if (_isNet) {
      out = LogicNet(name: _out, width: outputWidth, naming: Naming.unnamed);
      final internalOut = addInOut(_out, out, width: outputWidth);

      var idx = 0;
      for (final swizzleInput in _swizzleInputs) {
        internalOut.quietlyMergeSubsetTo(swizzleInput as LogicNet, start: idx);
        idx += swizzleInput.width;
      }
    } else {
      out = addOutput(_out, width: outputWidth);

      // so that you can't assign the output of a (Logic) swizzle
      out.makeUnassignable(
          reason:
              'The output of a (non-LogicNet) Swizzle ($this) is read-only.');

      _execute(); // for initial values
      for (final swizzleInput in _swizzleInputs) {
        swizzleInput.glitch.listen((args) {
          _execute();
        });
      }
    }
  }

  /// Executes the functional behavior of this gate.
  void _execute() {
    final updatedVal =
        LogicValue.ofIterable(_swizzleInputs.map((e) => e.value));
    out.put(updatedVal);
  }

  @override
  String get resultSignalName => _out;

  @override
  String inlineVerilog(Map<String, String> inputs) {
    assert(
        inputs.length == _swizzleInputs.length ||
            (inputs.length == _swizzleInputs.length + 1 && _isNet),
        'This swizzle has ${_swizzleInputs.length} inputs,'
        ' but saw $inputs with ${inputs.length} values.');

    final inputStr = _swizzleInputs.reversed
        .where((e) => e.width > 0)
        .map((e) => inputs[e.name])
        .join(',');
    return '{$inputStr}';
  }
}
