/// Copyright (C) 2021-2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// pipeline.dart
/// Pipeline generators
///
/// 2021 October 11
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:rohd/rohd.dart';

/// Information and accessors associated with a [Pipeline] stage.
class PipelineStageInfo {
  /// The index of the current stage in the associated [Pipeline].
  final int stage;

  /// The [Pipeline] associated with this object.
  final Pipeline _pipeline;

  PipelineStageInfo._(this._pipeline, this.stage);

  /// Returns a staged version of [identifier] at the current stage, adjusted
  /// by the amount of [stageAdjustment].
  ///
  /// Typically, your pipeline will consist of a lot of `p.get(x)` type calls,
  /// but if you want to combinationally access a value of a signal from another
  /// stage, you can access it relatively using [stageAdjustment].  For
  /// example, `p.get(x, -1)` will access the value of `x` one stage prior.
  Logic get(Logic identifier, [int stageAdjustment = 0]) =>
      _pipeline.get(identifier, stage + stageAdjustment);

  /// Returns a staged version of [identifier] at the specified
  /// absolute [stageIndex].
  Logic getAbs(Logic identifier, int stageIndex) =>
      _pipeline.get(identifier, stageIndex);
}

class _PipeStage {
  final Map<Logic, Logic> input = {};
  final Map<Logic, Logic> main = {};
  final Map<Logic, Logic> output = {};
  Logic? stall;

  final List<Conditional> Function(PipelineStageInfo p) operation;
  _PipeStage(this.operation);

  void _addLogic(Logic newLogic, int index) {
    input[newLogic] =
        Logic(name: '${newLogic.name}_stage${index}_i', width: newLogic.width);
    output[newLogic] =
        Logic(name: '${newLogic.name}_stage${index}_o', width: newLogic.width);
    main[newLogic] =
        Logic(name: '${newLogic.name}_stage$index', width: newLogic.width);
  }
}

/// A simple pipeline, separating arbitrary combinational logic by flop stages.
class Pipeline {
  /// The clock whose positive edge triggers the flops in this pipeline.
  final Logic clk;

  /// An optional reset signal for all pipelined signals.
  final Logic? reset;

  /// All the [_PipeStage]s for this [Pipeline]
  late final List<_PipeStage> _stages;

  /// Returns the number of stages in this pipeline.
  int get _numStages => _stages.length;

  /// A map of reset values for every signal.
  late final Map<Logic, dynamic> _resetValues;

  /// Constructs a simple pipeline, separating arbitrary combinational logic by
  /// flop stages.
  ///
  /// Each stage in the list [stages] is a function whose sole parameter is a
  /// [PipelineStageInfo] object and which returns a [List] of [Conditional]
  /// objects.  Each stage can be thought of as being the contents of a
  /// [Combinational] block.  Use the [PipelineStageInfo] object to grab
  /// signals for a given pipe stage.  Flops are positive edge triggered
  /// based on [clk].
  ///
  /// Signals to be pipelined can optionally be specified in the [signals]
  /// list.  Any signal referenced in a stage via the [PipelineStageInfo]
  /// will automatically be included in the entire pipeline.
  ///
  /// If a [reset] signal is provided, then it will be consumed as an
  /// active-high reset for every signal through the pipeline.  The default
  /// reset value is 0 for all signals, but that can be overridden by
  /// setting [resetValues] to the desired value.  The values specified
  /// in [resetValues] should be a type acceptable to [Logic]'s `put` function.
  ///
  /// Each stage can be stalled independently using [stalls], where every index
  ///  of [stalls] corresponds to the index of the stage to be stalled.  When
  /// a stage's stall is asserted, the output of that stage will not change.
  Pipeline(this.clk,
      {List<List<Conditional> Function(PipelineStageInfo p)> stages = const [],
      List<Logic?>? stalls,
      List<Logic> signals = const [],
      Map<Logic, Const> resetValues = const {},
      this.reset}) {
    _stages = stages.map(_PipeStage.new).toList();
    _stages.add(_PipeStage((p) => [])); // output stage

    if (_numStages == 0) {
      return;
    }

    _resetValues = Map.from(resetValues);

    _setStalls(stalls);

    signals.forEach(_add);

    final combMiddles = <List<Conditional>>[];
    for (var i = 0; i < _numStages; i++) {
      final combMiddle = _stages[i].operation(PipelineStageInfo._(this, i));
      combMiddles.add(combMiddle);
    }

    for (var stageIndex = 0; stageIndex < _numStages; stageIndex++) {
      Combinational([
        for (Logic l in _registeredLogics)
          get(l, stageIndex) < _i(l, stageIndex),
        ...combMiddles[stageIndex],
        for (Logic l in _registeredLogics)
          _o(l, stageIndex) < get(l, stageIndex),
      ], name: 'comb_stage$stageIndex');
    }
  }

  /// Sets up the stall signals across [_stages].
  void _setStalls(List<Logic?>? stalls) {
    if (stalls != null) {
      if (stalls.length != _numStages - 1) {
        throw Exception('Stall list length (${stalls.length}) must match '
            'number of stages (${_numStages - 1}).');
      }
      for (var i = 0; i < _numStages - 1; i++) {
        final stall = stalls[i];
        if (stall == null) {
          continue;
        }
        if (stall.width != 1) {
          throw Exception('Stall signal must be 1 bit, but found $stall.');
        }
        _stages[i].stall = stall;
      }
    }
  }

  /// Adds a new signal to be pipelined across all stages.
  void _add(Logic newLogic) {
    dynamic resetValue;
    if (_resetValues.containsKey(newLogic)) {
      resetValue = _resetValues[newLogic];
    }

    for (var i = 0; i < _stages.length; i++) {
      _stages[i]._addLogic(newLogic, i);
    }

    _stages[0].input[newLogic]! <= newLogic;
    final ffAssigns = <Conditional>[];
    for (var i = 1; i < _stages.length; i++) {
      ffAssigns.add(_i(newLogic, i) < _o(newLogic, i - 1));
    }

    var ffAssignsWithStall =
        List<Conditional>.generate(_numStages - 1, (index) {
      final stall = _stages[index].stall;
      final ffAssign = ffAssigns[index] as ConditionalAssign;
      final driver = stall != null
          ? mux(stall, ffAssign.receiver, ffAssign.driver)
          : ffAssign.driver;
      return ffAssign.receiver < driver;
    });

    if (reset != null) {
      ffAssignsWithStall = <Conditional>[
        IfBlock([
          Iff(
            reset!,
            ffAssigns.map((conditional) {
              conditional as ConditionalAssign;
              return conditional.receiver < (resetValue ?? 0);
            }).toList(),
          ),
          Else(ffAssignsWithStall)
        ])
      ];
    }
    Sequential(clk, ffAssignsWithStall, name: 'ff_${newLogic.name}');
  }

  /// The stage input for a signal associated with [logic] to [stageIndex].
  ///
  /// This is the output of the previous flop.
  Logic _i(Logic logic, [int? stageIndex]) {
    stageIndex ??= _stages.length - 1;
    final stageLogic = _stages[stageIndex].input[logic]!;
    return stageLogic;
  }

  /// The stage output for a signal associated with [logic] to [stageIndex].
  ///
  /// This is the input to the next flop.
  Logic _o(Logic logic, [int? stageIndex]) {
    stageIndex ??= _stages.length - 1;
    final stageLogic = _stages[stageIndex].output[logic]!;
    return stageLogic;
  }

  /// Returns true if [logic] is already a part of this [Pipeline].
  bool _isRegistered(Logic logic) => _stages[0].main.containsKey(logic);

  /// Returns a list of all [Logic]s which are part of this [Pipeline].
  Iterable<Logic> get _registeredLogics => _stages[0].main.keys;

  /// Gets the pipelined version of [logic].  By default [stageIndex] is the
  /// last stage (the output of the pipeline).
  ///
  /// If the signal is not already a part of this [Pipeline], the signal will be
  /// added to the [Pipeline].  Use [stageIndex] to select the value of [logic]
  /// at a specific stage of the pipeline.
  Logic get(Logic logic, [int? stageIndex]) {
    if (!_isRegistered(logic)) {
      _add(logic);
    }

    stageIndex ??= _stages.length - 1;

    final stageLogic = _stages[stageIndex].main[logic]!;
    return stageLogic;
  }
}

/// A pipeline that implements Ready/Valid protocol at each stage.
class ReadyValidPipeline extends Pipeline {
  /// Indicates that valid contents are ready to be recieved
  /// at the output of the pipeline.
  late final Logic validPipeOut;

  /// Indicates that the pipeline is ready to accept new content.
  late final Logic readyPipeIn;

  /// Indicates that the input to the pipeline is valid.
  final Logic validPipeIn;

  /// Indicates that the receiver of the output of the pipeline
  /// is ready to pull out of the pipeline.
  final Logic readyPipeOut;

  /// Constructs a pipeline with Ready/Valid protocol at each stage.
  ///
  /// The [validPipeIn] signal indicates that the input to the pipeline
  /// is valid.  The [readyPipeOut] signal indicates that the receiver
  /// of the output of the pipeline is ready to pull out of the pipeline.
  ///
  /// The [validPipeOut] signal indicates that valid contents are ready
  /// to be received at the output of the pipeline.  The [readyPipeIn]
  /// signal indicates that the pipeline is ready to accept new content.
  ///
  /// The pipeline will only progress through any stage, including the
  /// output, if both valid and ready are asserted at the same time.  This
  /// pipeline is capable of having bubbles, but they will collapse if
  /// downstream stages are backpressured.
  ///
  /// If contents are pushed in when the pipeline is not ready, they
  /// will be dropped.
  ReadyValidPipeline(
    super.clk,
    this.validPipeIn,
    this.readyPipeOut, {
    List<List<Conditional> Function(PipelineStageInfo p)> stages = const [],
    super.resetValues,
    List<Logic> signals = const [],
    super.reset,
  }) : super(
          stages: stages,
          signals: [validPipeIn, ...signals],
          stalls: List.generate(
              stages.length, (index) => Logic(name: 'stall_$index')),
        ) {
    final valid = validPipeIn;

    final stalls = _stages.map((stage) => stage.stall).toList()
      ..removeLast(); // garbage value at the end

    final readys =
        List.generate(stages.length, (index) => Logic(name: 'ready_$index'))
          ..add(readyPipeOut);

    for (var i = 0; i < stalls.length; i++) {
      readys[i] <= ~get(valid, i + 1) | readys[i + 1];
      stalls[i]! <= get(valid, i + 1) & ~readys[i + 1];
    }

    validPipeOut = get(valid);
    readyPipeIn = readys[0];
  }
}
