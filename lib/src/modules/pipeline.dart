/// Copyright (C) 2021 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
/// 
/// pipeline.dart
/// Pipeline generators
/// 
/// 2021 October 11
/// Author: Max Korbel <max.korbel@intel.com>
/// 

import 'package:rohd/rohd.dart';

class PipelineStageInfo {
  final int stage;
  final Pipeline _pipeline;
  PipelineStageInfo._(this._pipeline, this.stage);
  Logic get(Logic identifier, [int stageAdjustment=0]) {
    return _pipeline.getAbs(identifier, stage+stageAdjustment);
  }
  Logic getAbs(Logic identifier, int stage) {
    return _pipeline.getAbs(identifier, stage);
  }  
}

class _PipeStage {
  Map<Logic,Logic> input = {};
  Map<Logic,Logic> main = {};
  Map<Logic,Logic> output = {};
  Logic? stall;

  List<Conditional> Function(PipelineStageInfo p) operation;
  _PipeStage(this.operation);

  void addLogic(Logic newLogic, int index) {
    input[newLogic] = Logic(name: newLogic.name + '_stage${index}_i', width: newLogic.width);
    output[newLogic] = Logic(name: newLogic.name + '_stage${index}_o', width: newLogic.width);
    main[newLogic] = Logic(name: newLogic.name + '_stage$index', width: newLogic.width);
  }
   
}

class Pipeline {
  final Logic clk;
  final Logic? reset;
  late final List<_PipeStage> _stages;
  int get _numStages => _stages.length;
  late final Map<Logic,Const> _resetValues;
  Pipeline(this.clk,
    {
      List<List<Conditional> Function(PipelineStageInfo p)> stages=const[],
      List<Logic?>? stalls,
      List<Logic> signals = const[],
      Map<Logic,Const> resetValues = const{},
      String name='pipeline', this.reset
    }) 
  {
    
    _stages = stages.map((stage) => _PipeStage(stage)).toList();
    _stages.add(_PipeStage((p)=>[])); // output stage

    if(_numStages == 0) return;

    _resetValues = Map.from(resetValues);

    if(stalls != null) {
      if(stalls.length != _numStages-1) throw Exception('Stall list length must match number of stages.');
      for(var i = 0; i < _numStages-1; i++) {
        var stall = stalls[i];
        if(stall == null) continue;
        if(stall.width != 1) throw Exception('Stall signal must be 1 bit');
        _stages[i].stall = stall;
      }      
    }

    for(var signal in signals) {
      _add(signal);
    }

    var combMiddles = <List<Conditional>>[];
    for(var i = 0; i < _numStages; i++) {
      var combMiddle = _stages[i].operation(PipelineStageInfo._(this, i));
      combMiddles.add(combMiddle);
    }

    for(var stage = 0; stage < _numStages; stage++) {
      Combinational(
        [
          ..._registeredLogics.map((logic) => getAbs(logic, stage) < _i(logic, stage)),
          ...combMiddles[stage],
          ..._registeredLogics.map((logic) => _o(logic, stage) < getAbs(logic, stage)),
        ],
        name: 'comb_stage$stage'
      );
    }

  }

  void _add(Logic newLogic) {
    //TODO: how to expose resetValue to user

    Const? resetValue;
    if(_resetValues.containsKey(newLogic)) {
      resetValue = _resetValues[newLogic];
    }

    for(var i = 0; i < _stages.length; i++) {
      _stages[i].addLogic(newLogic, i);
    }

    _stages[0].input[newLogic]! <= newLogic;
    var ffAssigns = <Conditional>[];
    for(var i = 1; i < _stages.length; i++) {
      ffAssigns.add(
        _i(newLogic, i) < _o(newLogic, i-1)
      );
    }

    var ffAssignsWithStall = List<Conditional>.generate(_numStages-1, 
      (index) {
        var stall = _stages[index].stall;
        var ffAssign = ffAssigns[index] as ConditionalAssign;
        var driver = stall != null ?
          Mux(stall, ffAssign.receiver, ffAssign.driver).y :
          ffAssign.driver;
        return ffAssign.receiver < driver;
      }
    );

    if(reset != null) {
      ffAssignsWithStall = <Conditional>[
        IfBlock([
          Iff(reset!, 
            ffAssigns.map((conditional) {
              conditional as ConditionalAssign;
              return conditional.receiver < (resetValue ?? 0);
            }).toList(),
          ),
          Else(
            ffAssignsWithStall
          )
        ])
      ];
    }
    FF(clk, ffAssignsWithStall, name: 'ff_${newLogic.name}');
  }

  Logic _i(Logic logic, [int? stage]) {
    stage = stage ?? _stages.length - 1;
    var stageLogic = _stages[stage].input[logic]!;
    return stageLogic;
  }
  Logic _o(Logic logic, [int? stage]) {
    stage = stage ?? _stages.length - 1;
    var stageLogic = _stages[stage].output[logic]!;
    return stageLogic;
  }
  
  bool _isRegistered(Logic logic) => _stages[0].main.containsKey(logic);
  Iterable<Logic> get _registeredLogics => _stages[0].main.keys;

  Logic getAbs(Logic logic, [int? stage]) {
    if(!_isRegistered(logic)) _add(logic);

    stage = stage ?? _stages.length - 1;

    var stageLogic = _stages[stage].main[logic]!;
    return stageLogic;
  }
}

class ReadyValidPipeline {
  late final Logic validPipeOut;
  late final Logic readyPipeIn;
  final Logic validPipeIn;
  final Logic readyPipeOut;
  late final Pipeline _pipeline;
  ReadyValidPipeline(Logic clk, this.validPipeIn, this.readyPipeOut, {
      List<List<Conditional> Function(PipelineStageInfo p)> stages=const[],
      Map<Logic,Const> resetValues = const{},
      List<Logic> signals = const[],
      String name='rvpipeline', Logic? reset,
    })
  {
    var valid = validPipeIn;

    var stalls = List.generate(stages.length, (index) => Logic(name: 'stall_$index'));

    var readys = List.generate(stages.length, (index) => Logic(name: 'ready_$index'));
    readys.add(readyPipeOut);

    _pipeline = Pipeline(clk,
      stages: stages,
      signals: [valid, ...signals],
      stalls: stalls,
      reset: reset,
      resetValues: resetValues
    );

    for(var i = 0; i < stalls.length; i++) {
      readys[i] <= ~_pipeline.getAbs(valid, i+1) | readys[i+1];
      stalls[i] <= _pipeline.getAbs(valid, i+1) & ~readys[i+1];
    }

    validPipeOut = _pipeline.getAbs(valid);
    readyPipeIn = readys[0];
  }

  Logic getAbs(Logic logic, [int? stage]) {
    return _pipeline.getAbs(logic, stage);
  }  
}