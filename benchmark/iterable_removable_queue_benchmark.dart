// import 'dart:io';

import 'dart:io';

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:rohd/src/collections/iterable_removable_queue.dart';
import "dart:developer";

class DummyElement {
  final Set<String> someSet = {};
  int value;
  DummyElement(this.value) {
    for (var i = 0; i < 100; i++) {
      someSet.add('item_${value}_$i');
    }
  }
}

class IterableRemovableQueueBenchmark extends BenchmarkBase {
  IterableRemovableQueueBenchmark() : super('IterableRemovableQueue');

  late final IterableRemovableQueue<DummyElement> queue;

  static const numElements = 100;
  static const numIterations = 10001;
  static const checkFrequency = 2000;

  @override
  void setup() {
    queue = IterableRemovableQueue<DummyElement>();
    for (var i = 0; i < numElements; i++) {
      queue.add(DummyElement(i));
    }
  }

  @override
  void run() {
    for (var iter = 0; iter < numIterations; iter++) {
      for (var i = 0; i < numElements; i++) {
        queue
          ..iterate(
            action: (item) => item.value + 1,
            // removeWhere: (item) => item.value == i, //TODO
          )
          ..add(DummyElement(i));
      }

      if (iter > 0 && iter % checkFrequency == 0) {
        final fileName = "iter$iter.heapsnapshot";
        NativeRuntime.writeHeapSnapshotToFile(fileName);
        final size = File(fileName).lengthSync();

        print('@$iter: Heap size is $size bytes.');
        if (size > 100 * 1000000) {
          print('***Very large heap!');
          break;
        }
      }
    }
    // NativeRuntime.writeHeapSnapshotToFile("newbuild.heapsnapshot");
    // exit(0);
  }
}

void main() {
  IterableRemovableQueueBenchmark().report();
  print("asdf");
}
