


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

class Pipeline {
  final List<List<Conditional> Function(PipelineStageInfo p)> _stages;
  late final List<Map<Logic,Logic>> _stageLogicMaps_i, _stageLogicMaps_o, _stageLogicMaps;
  final Logic clk;
  final Logic? reset;
  int get _numStages => _stages.length;
  Pipeline(this.clk, {List<List<Conditional> Function(PipelineStageInfo p)> stages=const[], String name='pipeline', this.reset}) :
    _stages = stages
  {

    if(_numStages == 0) return;

    _stageLogicMaps_i = List.generate(_numStages, (index) => {});
    _stageLogicMaps = List.generate(_numStages, (index) => {});
    _stageLogicMaps_o = List.generate(_numStages, (index) => {});

    var combMiddles = <List<Conditional>>[];
    for(var i = 0; i < _numStages; i++) {
      var combMiddle = _stages[i](PipelineStageInfo._(this, i));
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

  void _add(Logic newLogic, {Const? resetValue}) {
    //TODO: how to expose resetValue to user

    for(var i = 0; i < _stages.length; i++) {
      _stageLogicMaps_i[i][newLogic] = Logic(name: newLogic.name + '_stage${i}_i', width: newLogic.width);
      _stageLogicMaps_o[i][newLogic] = Logic(name: newLogic.name + '_stage${i}_o', width: newLogic.width);
      _stageLogicMaps[i][newLogic] = Logic(name: newLogic.name + '_stage$i', width: newLogic.width);
    }

    _stageLogicMaps_i[0][newLogic]! <= newLogic;
    var ffAssigns = <Conditional>[];
    for(var i = 1; i < _stages.length; i++) {
      ffAssigns.add(
        _i(newLogic, i) < _o(newLogic, i-1)
      );
    }
    if(reset != null) {
      ffAssigns = <Conditional>[
        If(reset!, 
        then:
          ffAssigns.map((conditional) {
            conditional as ConditionalAssign;
            return conditional.receiver < (resetValue ?? 0);
          }).toList(),
        orElse: 
          ffAssigns
        )
      ];
    }
    FF(clk, ffAssigns, name: 'ff_${newLogic.name}');
  }

  Logic _i(Logic logic, [int? stage]) {
    stage = stage ?? _stages.length - 1;
    var stageLogic = _stageLogicMaps_i[stage][logic]!;
    return stageLogic;
  }
  Logic _o(Logic logic, [int? stage]) {
    stage = stage ?? _stages.length - 1;
    var stageLogic = _stageLogicMaps_o[stage][logic]!;
    return stageLogic;
  }

  
  bool _isRegistered(Logic logic) => _stageLogicMaps[0].containsKey(logic);
  Iterable<Logic> get _registeredKeys => _stageLogicMaps[0].keys;

  Logic get(Logic logic, [int? stage]) {
    if(!_isRegistered(logic)) _add(logic);

    stage = stage ?? _stages.length - 1;

    var stageLogic = _stageLogicMaps[stage][logic]!;
    return stageLogic;
  }
}

class PipelineWrapper extends Module {
  
  Logic get b => output('b');
  PipelineWrapper(Logic clk, Logic a) : super(name: 'pipeline_wrapper') {
    clk = addInput('clk', clk);
    a = addInput('a', a);
    var b = addOutput('b');

    var pipeline = Pipeline(clk,
      stages: [
        (p) => [
          p.get(a) < p.get(a) | p.get(b)
        ],
        (p) => [
          p.get(a) < p.get(a) & p.get(b)
        ],
        (p) => [
        ],
      ], reset: Logic(name: 'reset')
    );
    b <= pipeline.get(b);
  }
}

void main() async {

  Logic a = Logic(name: 'a');
  Logic clk = Logic(name: 'clk');
  var pipem = PipelineWrapper(clk, a);

  await pipem.build();
  File('tmp.sv').writeAsStringSync(pipem.generateSynth());

  // Pipeline(inputs: [a, b, c], stages: [
  //   (info) {
  //     Logic d = info.new();
  //     info.new(d);
  //     d = info.current(a) + info.current(b);

  //   },
  //   ...List.generate(8, (index) => null),
  //   (info) {
  //     info.past(-1, a) + ...
  //   },
  //   (info) {

  //   }
  // ]);
}