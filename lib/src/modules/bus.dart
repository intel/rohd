// Copyright (C) 2021-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// bus.dart
// Definition for modules related to bus operations
//
// 2021 August 2
// Author: Max Korbel <max.korbel@intel.com>

import 'dart:math' show max;

import 'package:meta/meta.dart';
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

  @internal
  @override
  bool get isWiresOnly => true;

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

  /// A regular expression that will have matches if an expression is a single
  /// bit select of a signal or packed array element.
  static final RegExp _singleBitSelectRegex =
      RegExp(r'^\(?([A-Za-z_][A-Za-z0-9_$]*(?:\[\d+\])*)\[(\d+)\]\)?$');

  /// The output port containing concatenated signals.
  late final Logic out;

  final List<Logic> _swizzleInputs = [];

  /// Whether this [Swizzle] is for [LogicNet]s.
  final bool _isNet;

  @internal
  @override
  bool get isWiresOnly => true;

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

    // Calculate all width descriptions upfront to determine alignment
    final validInputs =
        _swizzleInputs.reversed.where((e) => e.width > 0).toList();
    final operands = _collapseContiguousBitSelects(validInputs, inputs);

    // If there's only one element, no need for width descriptions
    if (operands.length == 1) {
      return operands.first.expression;
    }

    final widthDescriptions = <({int upper, int? lower})>[];
    var upperIndex = out.width - 1;

    // First pass: calculate all width descriptions
    for (final operand in operands) {
      if (operand.width > 1) {
        final lowerIndex = upperIndex - operand.width + 1;
        widthDescriptions.add((upper: upperIndex, lower: lowerIndex));
      } else {
        widthDescriptions.add((upper: upperIndex, lower: null));
      }
      upperIndex -= operand.width;
    }

    // Find maximum width for alignment
    final maxUpperWidth = widthDescriptions.isEmpty
        ? 0
        : widthDescriptions
            .map((desc) => desc.upper.toString().length)
            .reduce(max);
    final maxLowerWidth =
        widthDescriptions.where((desc) => desc.lower != null).isEmpty
            ? 0
            : widthDescriptions
                .where((desc) => desc.lower != null)
                .map((desc) => desc.lower!.toString().length)
                .reduce(max);

    // Second pass: generate aligned output
    upperIndex = out.width - 1;
    final inputLines = <String>[];
    var descIndex = 0;

    for (final operand in operands) {
      final desc = widthDescriptions[descIndex++];

      String alignedDesc;
      if (desc.lower != null) {
        final paddedUpper = desc.upper.toString().padLeft(maxUpperWidth);
        final paddedLower = desc.lower!.toString().padLeft(maxLowerWidth);
        alignedDesc = '$paddedUpper:$paddedLower';
      } else {
        // For single bits, right-align to the total width (upper:lower format)
        final totalWidth =
            maxUpperWidth + (maxLowerWidth > 0 ? 1 + maxLowerWidth : 0);
        alignedDesc = desc.upper.toString().padLeft(totalWidth);
      }

      upperIndex -= operand.width;
      final maybeComma =
          upperIndex >= 0 ? ',' : ' '; // space at end for alignment
      inputLines.add('${operand.expression}$maybeComma /* $alignedDesc */');
    }

    return '''
{
${inputLines.join('\n')}
}''';
  }

  /// Rewrites runs of adjacent descending single-bit selects from the same
  /// packed signal into wider SystemVerilog slices.
  ///
  /// For example, `a[7], a[6], a[5]` becomes `a[7:5]`, and
  /// `a[0][1], a[0][0]` becomes `a[0][1:0]`. Ascending runs are intentionally
  /// left expanded because SystemVerilog slices cannot reverse bit order with
  /// `lower:upper` syntax.
  List<({String expression, int width})> _collapseContiguousBitSelects(
    List<Logic> validInputs,
    Map<String, String> inputs,
  ) {
    final operands = <({String expression, int width})>[];

    var index = 0;
    while (index < validInputs.length) {
      final input = validInputs[index];
      final expression = inputs[input.name]!;
      final selectedBit = _singleBitSelect(input, expression);
      if (selectedBit == null) {
        operands.add((expression: expression, width: input.width));
        index++;
        continue;
      }

      var lowerIndex = selectedBit.index;
      var endIndex = index + 1;
      while (endIndex < validInputs.length) {
        final nextInput = validInputs[endIndex];
        final nextExpression = inputs[nextInput.name]!;
        final nextSelectedBit = _singleBitSelect(nextInput, nextExpression);
        if (nextSelectedBit == null ||
            nextSelectedBit.source != selectedBit.source ||
            nextSelectedBit.index != lowerIndex - 1) {
          break;
        }

        lowerIndex = nextSelectedBit.index;
        endIndex++;
      }

      if (endIndex == index + 1) {
        operands.add((expression: expression, width: input.width));
      } else {
        operands.add((
          expression: '${selectedBit.source}[${selectedBit.index}:$lowerIndex]',
          width: endIndex - index,
        ));
      }
      index = endIndex;
    }

    return operands;
  }

  /// Parses [expression] as a single-bit select of a packed signal when it is
  /// safe to participate in slice collapsing.
  ///
  /// Returns `null` for multi-bit inputs, non-select expressions, or selects
  /// sourced from unpacked arrays.
  ({String source, int index})? _singleBitSelect(
    Logic input,
    String expression,
  ) {
    if (input.width != 1 || _hasUnpackedArraySource(input.srcConnection)) {
      return null;
    }

    final match = _singleBitSelectRegex.firstMatch(expression);
    if (match == null) {
      return null;
    }

    return (source: match.group(1)!, index: int.parse(match.group(2)!));
  }

  /// Walks up [logic]'s containing structures to detect unpacked arrays.
  ///
  /// SystemVerilog packed slices are not interchangeable with unpacked array
  /// indexing, so any unpacked array source disables bit-select collapsing.
  bool _hasUnpackedArraySource(Logic? logic) {
    var current = logic;
    while (current?.parentStructure != null) {
      final parentStructure = current!.parentStructure!;
      if (parentStructure is LogicArray &&
          parentStructure.numUnpackedDimensions > 0) {
        return true;
      }
      current = parentStructure;
    }

    return false;
  }
}
