/// Copyright (C) 2021 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
/// 
/// pipeline.dart
/// Pipelines!
/// 
/// 2021 October 11
/// Author: Max Korbel <max.korbel@intel.com>
/// 


import 'dart:io';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/module.dart';

class PipelineStageInfo {
  final int stage;
  Pipeline _pipeline;
  PipelineStageInfo._(this._pipeline, this.stage);
  Logic get(Logic identifier, [int stageAdjustment=0]) {
    return _pipeline.get(identifier, stage+stageAdjustment);
  }
  Logic getAbs(Logic identifier, int stage) {
    return _pipeline.get(identifier, stage);
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
  Pipeline(this.clk,
    {
      List<List<Conditional> Function(PipelineStageInfo p)> stages=const[],
      List<Logic?>? stalls,
      List<Logic> signals = const[],
      String name='pipeline', this.reset
    }) 
  {

    _stages = stages.map((e) => _PipeStage(e)).toList();
    _stages.add(_PipeStage((p)=>[])); // output stage

    if(_numStages == 0) return;

    for(var signal in signals) {
      _add(signal);
    }

    if(stalls != null) {
      if(stalls.length != _numStages-1) throw Exception('Stall list length must match number of stages.');
      for(var i = 0; i < _numStages-1; i++) {
        var stall = stalls[i];
        if(stall == null) continue;
        if(stall.width != 1) throw Exception('Stall signal must be 1 bit');
        _stages[i].stall = stall;
      }      
    }

    var combMiddles = <List<Conditional>>[];
    for(var i = 0; i < _numStages; i++) {
      var combMiddle = _stages[i].operation(PipelineStageInfo._(this, i));
      combMiddles.add(combMiddle);
    }

    for(var stage = 0; stage < _numStages; stage++) {
      Combinational(
        [
          ..._registeredKeys.map((logic) => get(logic, stage) < _i(logic, stage)),
          ...combMiddles[stage],
          ..._registeredKeys.map((logic) => _o(logic, stage) < get(logic, stage)),
        ],
        name: 'comb_stage$stage'
      );
    }

  }

  Logic stall(int index) {
    if(_stages[index].stall == null) {
      _stages[index].stall = Logic(name: 'stall_$index');
    }
    return _stages[index].stall!;
  }

  void _add(Logic newLogic, {Const? resetValue}) {
    //TODO: how to expose resetValue to user

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
  Iterable<Logic> get _registeredKeys => _stages[0].main.keys;

  Logic get(Logic logic, [int? stage]) {
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
      String name='rvpipeline', Logic? reset,
    })
  {
    var ready = Logic(name: 'ready');
    var valid = validPipeIn;

    var stalls = List.generate(stages.length, (index) => Logic(name: 'stall_$index'));
  
    var newStages = <List<Conditional> Function(PipelineStageInfo)>[];
    for(var i = 0; i < stages.length-1; i++) {
      var stage = stages[i];
      newStages.add(
        (PipelineStageInfo p) => [
          p.get(ready) < ~p.get(valid, 1) | p.get(ready, 1),
          ...stage(p)
        ]
      );
    }
    newStages.add((p) => [
      p.get(ready) < readyPipeOut,
      ...stages[stages.length-1](p)
    ]);


    _pipeline = Pipeline(clk,
      stages: newStages,
      signals: [validPipeIn],
      stalls: stalls,
    );

    for(var i = 0; i < stalls.length; i++) {
      stalls[i] <= ~_pipeline.get(ready, i);
    }

    validPipeOut = _pipeline.get(valid);
    readyPipeIn = _pipeline.get(ready, 0);
  }

  Logic get(Logic logic, [int? stage]) {
    return _pipeline.get(logic, stage);
  }  
}

// class PipelineWrapper extends Module {
  
//   Logic get b => output('b');
//   PipelineWrapper(Logic clk, Logic a) : super(name: 'pipeline_wrapper') {
//     clk = addInput('clk', clk);
//     a = addInput('a', a);
//     var b = addOutput('b');

//     // var pipeline = Pipeline(clk, stalls: [null, Logic(name:'stall'), null],
//     //   stages: [
//     //     (p) => [
//     //       p.get(a) < p.get(a) | p.get(b)
//     //     ],
//     //     (p) => [
//     //       p.get(a) < p.get(a) & p.get(b)
//     //     ],
//     //     (p) => [
//     //     ],
//     //   ], reset: Logic(name: 'reset')
//     // );
//     // b <= pipeline.get(b);

//     Logic validPipeIn = Logic(name: 'validPipeIn');
//     Logic readyPipeOut = Logic(name: 'readyPipeOut');
//     var pipeline = ReadyValidPipeline(clk, validPipeIn, readyPipeOut,
//       stages: [
//         (p) => [
//           p.get(a) < p.get(a) | p.get(b)
//         ],
//         (p) => [
//           p.get(a) < p.get(a) & p.get(b)
//         ],
//         (p) => [
//         ],
//       ], reset: Logic(name: 'reset')
//     );
//     b <= pipeline.get(b);
//   }
// }

// void main() async {

//   Logic a = Logic(name: 'a');
//   Logic clk = Logic(name: 'clk');
//   var pipem = PipelineWrapper(clk, a);

//   await pipem.build();
//   File('tmp.sv').writeAsStringSync(pipem.generateSynth());
// }