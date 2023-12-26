import 'package:rohd/rohd.dart';
import 'package:rohd/src/interfaces/interfaces.dart';

abstract class HandshakeInterface extends PairInterface {}

abstract class ReadyValidInterface extends HandshakeInterface {
  late final Logic ready, valid;
}

class ReadyAndValidInterface extends ReadyValidInterface {}

class ReadyThenValidInterface extends ReadyValidInterface {}

class ValidThenReadyInterface extends ReadyValidInterface {}
// etc...

class CreditedInterface extends HandshakeInterface {
  late final Logic valid, creditReturn;
  // init flow, etc.
}

class HandshakePipeline {
  HandshakeInterface upstream, downstream;
  HandshakePipeline(
    this.upstream,
    List<HandshakePipeStage> elements,
    this.downstream,
  ) {
    for (var element in elements) {
      if (element
          is HandshakePipeStage<ReadyAndValidInterface, CreditedInterface>) {}
    }
  }
}

class HandshakePipeStage<UpType extends HandshakeInterface,
    DownType extends HandshakeInterface> {
  void Function(UpType upstream, DownType downstream) stageDefinition;
  HandshakePipeStage(this.stageDefinition);
}

class FanOut {
  FanOut(HandshakeInterface upstream, List<HandshakeInterface> downstream);
}

class FanIn {
  FanIn(List<HandshakeInterface> upstream, HandshakeInterface downstream);
}

class FanToFan {
  FanToFan(
      List<HandshakeInterface> upstream, List<HandshakeInterface> downstream);
}

class MyModule {
  ReadyAndValidInterface upstream;
  CreditedInterface downstream;
  MyModule(this.upstream, this.downstream, Logic clk);
}

void main() {
  Logic clk = Logic();
  HandshakePipeline(
    CreditedInterface(),
    [
      HandshakePipeStage<ReadyAndValidInterface, CreditedInterface>(
        (upstream, downstream) => MyModule(upstream, downstream, clk),
      ),
      HandshakePipeStage((upstream, downstream) => HandshakePipeline(
            upstream,
            [],
            downstream,
          )),
      HandshakePipeStage<ReadyAndValidInterface, CreditedInterface>(
        (upstream, downstream) => MyModule(upstream, downstream, clk),
      ),
      HandshakePipeStage((upstream, downstream) {
        List<HandshakeInterface> split = [
          ValidThenReadyInterface(),
          ReadyThenValidInterface(),
        ];

        FanOut(upstream, split);

        // ...

        FanIn(split, downstream);
      }),
    ],
    ValidThenReadyInterface(),
  );
}
