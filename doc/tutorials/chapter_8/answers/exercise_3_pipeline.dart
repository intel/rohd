import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

class Pipeline4Stages extends Module {
  late final Pipeline pipeline;

  Logic get result => output('result');

  Pipeline4Stages(Logic clk, Logic reset, Logic a)
      : super(name: 'pipeline_4_stages') {
    clk = addInput('clk', clk);
    reset = addInput(reset.name, reset);
    a = addInput(a.name, a, width: a.width);

    final result = addOutput('result', width: 64);

    pipeline = Pipeline(clk, reset: reset, resetValues: {
      result: Const(0)
    }, stages: [
      ...List.generate(
          4, (stage) => (p) => [p.get(a) < p.get(a) + (p.get(a) * stage)])
    ]);

    result <= pipeline.get(a).zeroExtend(result.width);
  }
}

void main(List<String> args) async {
  test('should return the the matching stage result if input is 5.', () async {
    final a = Logic(name: 'a', width: 8);
    final reset = Logic(name: 'reset');
    final clk = SimpleClockGenerator(10).clk;

    final pipe = Pipeline4Stages(clk, reset, a);
    await pipe.build();

    // print(pipe.generateSynth());

    a.inject(5);
    reset.inject(1);

    Simulator.registerAction(10, () => reset.put(0));

    WaveDumper(pipe, outputPath: 'answer_1.vcd');

    Simulator.registerAction(50, () async {
      // stage 4 / result: 30 + (30 * 3) = 120
      expect(pipe.result.value.toInt(), 120);
    });

    Simulator.setMaxSimTime(100);
    await Simulator.run();
  });
}
