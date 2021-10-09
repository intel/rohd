

import 'package:rohd/rohd.dart';
import 'package:rohd/src/module.dart';


class PipelineStageInfo {
  final int stage;
  Pipeline _pipeline;
  PipelineStageInfo._(this._pipeline, this.stage);
  Logic i(Logic identifier, [int stageAdjustment=0]) {
    return _pipeline.i(identifier, stage+stageAdjustment);
  }
  Logic o(Logic identifier, [int stageAdjustment=0]) {
    return _pipeline.o(identifier, stage+stageAdjustment);
  }

  Logic iAbs(Logic identifier, int stage) {
    return _pipeline.i(identifier, stage);
  }
  Logic oAbs(Logic identifier, int stage) {
    return _pipeline.o(identifier, stage);
  }
  
  void add(Logic newLogic) {
    _pipeline.add(newLogic);
  }
}

class Pipeline {
  final List<Logic> _inputs;
  final List<void Function(PipelineStageInfo p)> _stages;
  late final List<Map<Logic,Logic>> _stageLogicMaps_i, _stageLogicMaps_o;
  final Logic clk;
  Pipeline(this.clk, {List<Logic> inputs=const[], List<Function(PipelineStageInfo p)> stages=const[], String name='pipeline'}) :
    _inputs = inputs, _stages = stages
  {
    _stageLogicMaps_i = List.generate(_stages.length, (index) => {});
    _stageLogicMaps_o = List.generate(_stages.length, (index) => {});

    for(var input in _inputs) {
      add(input);
    }

    for(var i = 0; i < _stages.length; i++) {
      _stages[i](PipelineStageInfo._(this, i));
    }

    _tieUpLooseEnds();
  }

  void _tieUpLooseEnds() {
    for(var i = 0; i < _stages.length; i++) {
      _stageLogicMaps_o[i].forEach((key, value) {
        if(value.srcConnection == null) {
          value <= _stageLogicMaps_i[i][key]!;
        }  
      });
    }
  }

  void add(Logic newLogic) {
    for(var i = 0; i < _stages.length; i++) {
      _stageLogicMaps_i[i][newLogic] = Logic(name: newLogic.name + '_stage${i}_i', width: newLogic.width);
      _stageLogicMaps_o[i][newLogic] = Logic(name: newLogic.name + '_stage${i}_o', width: newLogic.width);
    }

    _stageLogicMaps_i[0][newLogic]! <= newLogic;
    var ffAssigns = <ConditionalAssign>[];
    for(var i = 1; i < _stages.length; i++) {
      ffAssigns.add(
        _stageLogicMaps_i[i][newLogic]! < _stageLogicMaps_o[i-1][newLogic]!
      );
    }
    FF(clk, ffAssigns, name: 'ff_${newLogic.name}');
  }

  Logic i(Logic logic, [int? stage]) {
    stage = stage ?? _stages.length - 1;
    var stageLogic = _stageLogicMaps_i[stage][logic]!;
    return stageLogic;
  }
  Logic o(Logic logic, [int? stage]) {
    stage = stage ?? _stages.length - 1;
    var stageLogic = _stageLogicMaps_o[stage][logic]!;
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
      inputs: [a, b],
      stages: [
        (p) {
          p.o(a) <= p.i(a) | p.i(b); 
        },
        (p) {
          p.o(a) <= p.i(a) & p.i(b);
        },
        (p) {},
      ]
    );
    b <= pipeline.o(b);
  }
}

void main() async {

  Logic a = Logic(name: 'a');
  Logic clk = Logic(name: 'clk');
  var pipem = PipelineWrapper(clk, a);

  await pipem.build();
  print(pipem.generateSynth());

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