import 'package:rohd/rohd.dart';

class ExampleSnippet extends Module {
  final int width;
  ExampleSnippet(Logic en, Logic reset, Logic clk,
      {this.width = 8, String name = 'example_snippet'})
      : super(name: name) {}
}

void main() async {
  final en = Logic(name: 'en');
  final reset = Logic(name: 'reset');
  final clk = SimpleClockGenerator(10).clk;

  final exampleSnippet = ExampleSnippet(en, reset, clk);
  await exampleSnippet.build();
}
