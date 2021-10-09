

import 'package:rohd/rohd.dart';
import 'package:rohd/src/module.dart';


class PipelineStageInfo {
  int _stageId;
  Pipeline _pipeline;
  PipelineStageInfo._(this._pipeline, this._stageId);
  Logic get(Logic identifier, [int stageAdjustment=0]) {
    return _pipeline._stageLogicMaps[_stageId + stageAdjustment][identifier]!;
  }
  Logic getAbs(Logic identifier, int stage) {
    return _pipeline._stageLogicMaps[stage][identifier]!;
  }
}

class Pipeline extends Module {
  final List<Logic> _inputs;
  final List<void Function(PipelineStageInfo p)> _stages;
  late final List<Map<Logic,Logic>> _stageLogicMaps;
  Logic get clk => input('clk');
  Pipeline(Logic clk, {List<Logic> inputs=const[], List<Function(PipelineStageInfo p)> stages=const[], String name='pipeline'}) :
    _inputs = inputs, _stages = stages, super(name: name)
  {
    addInput('clk', clk);
    _stageLogicMaps = List.generate(_stages.length, (index) => {});
    for(var input in _inputs) {
      add(input);
    }

    for(var i = 0; i < _stages.length; i++) {
      _stages[i](PipelineStageInfo._(this, i));
    }
  }

  void add(Logic newLogic, {String? inputName}) {
    inputName = inputName ?? newLogic.name;
    var newInput = addInput(inputName, newLogic, width: newLogic.width);

    for(var i = 0; i < _stageLogicMaps.length; i++) {
      var stageLogic = Logic(name: inputName + '_stage$i', width: newLogic.width);
      _stageLogicMaps[i][newLogic] = stageLogic;
    }

    _stageLogicMaps[0][newLogic]! <= newInput;
    for(var i = 1; i < _stageLogicMaps.length; i++) {
      _stageLogicMaps[i][newLogic]! <= FlipFlop(clk, _stageLogicMaps[i-1][newLogic]!).q; 
    } 
  }

  Logic get(Logic logic, [int? stage]) {
    stage = stage ?? _stages.length - 1;
    var stageLogic = _stageLogicMaps[stage][logic]!;
    var outName = stageLogic.name + '_out';
    try {
      return output(outName);
    } catch (_) {
      return addOutput(outName);
    }
  }
}

void main() async {

  Logic a = Logic(name: 'a');
  Logic clk = Logic(name: 'clk');
  var pipeline = Pipeline(clk,
    inputs: [a],
    stages: [
      (p) {},
      (p) {},
      (p) {},
    ]
  );

  await pipeline.build();
  print(pipeline.generateSynth());

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