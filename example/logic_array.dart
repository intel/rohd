// Though we usually avoid them, for this example,
// allow `print` messages (disable lint):
// ignore_for_file: avoid_print

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

class ArrayIndexExample extends Module {
  Logic get selectIndexValueArrayA => output('selectIndexValueArrayA');
  Logic get selectFromValueArrayA => output('selectFromValueArrayA');
  Logic get selectIndexValueArrayB => output('selectIndexValueArrayB');
  Logic get selectFromValueArrayB => output('selectFromValueArrayB');

  ArrayIndexExample(
      Logic in1, // first example using Logic
      Logic in2, // first example using Logic
      Logic in3, // first example using Logic
      Logic index,
      Logic defaultValue,
      Logic selectIndexValueArrayA,
      Logic selectFromValueArrayA,
      LogicArray arrayB, // second example using LogicArray
      Logic selectIndexValueArrayB,
      Logic selectFromValueArrayB)
      : super(name: 'array_index_example') {
    // First example using Logic
    in1 = addInput(in1.name, in1, width: in1.width);
    in2 = addInput(in2.name, in2, width: in2.width);
    in3 = addInput(in3.name, in3, width: in3.width);
    index = addInput(index.name, index, width: index.width);
    defaultValue =
        addInput(defaultValue.name, defaultValue, width: defaultValue.width);
    selectIndexValueArrayA =
        addOutput('selectIndexValueArrayA', width: in1.width);
    selectFromValueArrayA =
        addOutput('selectFromValueArrayA', width: in1.width);

    final arrayA = <Logic>[in1, in2, in3];

    selectIndexValueArrayA <=
        arrayA.selectIndex(index, defaultValue: defaultValue);
    selectFromValueArrayA <=
        index.selectFrom(arrayA, defaultValue: defaultValue);

    // Second example using LogicArray
    arrayB = addInputArray('arrayB', arrayB,
        dimensions: arrayB.dimensions, elementWidth: arrayB.elementWidth);
    selectIndexValueArrayB =
        addOutput('selectIndexValueArrayB', width: arrayB.elementWidth);
    selectFromValueArrayB =
        addOutput('selectFromValueArrayB', width: arrayB.elementWidth);

    selectIndexValueArrayB <=
        arrayB.elements.selectIndex(index, defaultValue: defaultValue);
    selectFromValueArrayB <=
        index.selectFrom(arrayB.elements, defaultValue: defaultValue);
  }
}

Future<void> main({bool noPrint = false}) async {
  // First example using Logic
  final inputA = Logic(name: 'inputA', width: 8); // id = 0
  final inputB = Logic(name: 'inputB', width: 8); // id = 1
  final inputC = Logic(name: 'inputC', width: 8); // id = 2
  final id = Logic(name: 'id', width: 3);
  final defaultValue = Const(0, width: 8);
  final selectIndexValueArrayA =
      Logic(name: 'selectIndexValueArrayA', width: 8);
  final selectFromValueArrayA = Logic(name: 'selectFromValueArrayA', width: 8);

  // Second example using LogicArray
  final arrayB =
      LogicArray([4], 8, name: 'arrayB'); // A 1D array with 4 8-bit elements
  final selectIndexValueArrayB =
      Logic(name: 'selectIndexValueArrayB', width: 8);
  final selectFromValueArrayB = Logic(name: 'selectFromValueArrayB', width: 8);

  final arrayIndexExample = ArrayIndexExample(
      inputA,
      inputB,
      inputC,
      id,
      defaultValue,
      selectIndexValueArrayA,
      selectFromValueArrayA,
      arrayB,
      selectIndexValueArrayB,
      selectFromValueArrayB);

  // Build the module
  await arrayIndexExample.build();

  // Set the Index value
  id.put(2);
  if (!noPrint) {
    print('id : ${id.value}');
  }
  // Set the input values for the first example
  inputA.put(1);
  inputB.put(2);
  inputC.put(3);
  if (!noPrint) {
    print('inputA: ${inputA.value}');
    print('inputB: ${inputB.value}');
    print('inputC: ${inputC.value}');
  }

  // Set the input values for the second example
  final listVal = <Logic>[
    Const(0, width: 8),
    Const(1, width: 8),
    Const(2, width: 8),
    Const(3, width: 8)
  ];

  for (var i = 0; i < 4; i++) {
    arrayB.elements[i] <= listVal[i];
  }

  if (!noPrint) {
    print('arrayB: ${arrayB.value}');
  }

  // Generate SystemVerilog code
  if (!noPrint) {
    print(arrayIndexExample.generateSynth());
  }

  // print the output values
  if (!noPrint) {
    print('${arrayIndexExample.selectIndexValueArrayA.value.toInt()}');
    print('${arrayIndexExample.selectFromValueArrayA.value.toInt()}');
    print('${arrayIndexExample.selectIndexValueArrayB.value.toInt()}');
    print('${arrayIndexExample.selectFromValueArrayB.value.toInt()}');
  }

  test('Test first example using Logic', () async {
    int expectedValue;
    switch (id.value.toInt()) {
      case 0:
        expectedValue = inputA.value.toInt();
      case 1:
        expectedValue = inputB.value.toInt();
      case 2:
        expectedValue = inputC.value.toInt();
      default:
        expectedValue = defaultValue.value.toInt();
    }
    expect(arrayIndexExample.selectIndexValueArrayA.value.toInt(),
        equals(expectedValue));
    expect(arrayIndexExample.selectFromValueArrayA.value.toInt(),
        equals(expectedValue));
  });

  test('Test second example using LogicArray', () async {
    expect(arrayIndexExample.selectIndexValueArrayB.value.toInt(),
        equals(listVal[id.value.toInt()].value.toInt()));
    expect(arrayIndexExample.selectFromValueArrayB.value.toInt(),
        equals(listVal[id.value.toInt()].value.toInt()));
  });
}
