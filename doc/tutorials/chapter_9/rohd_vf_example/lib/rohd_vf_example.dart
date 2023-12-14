import 'dart:async';
import 'dart:collection';
import 'package:logging/logging.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd_vf/rohd_vf.dart';
import '../../counter.dart';

// The DUT to test.
class TopTB {
  // Instance of DUT.
  late final MyCounter counter;

  static const int width = 8;

  TopTB() {
    // Build an instance of the interface to be used in Counter.
    final intf = MyCounterInterface();

    // connect a generated clock to the interface.
    intf.clk <= SimpleClockGenerator(10).clk;

    // Create the DUT, passing it to our interface.
    counter = MyCounter(intf);
  }
}

/// A [SequenceItem] represents a collection of information to transmit across
/// an interface. A typical use case would be an object representing a
/// transaction to be driven over a standardized hardware interface.
class MySeqItem extends SequenceItem {
  // your control pin
  // in this case is enable pin
  final bool enable;
  MySeqItem({required this.enable});

  int get en => enable ? 1 : 0;

  @override
  String toString() => 'enable=$enable';
}

// Sending stimulus through the testbench to the device under test is done by
// passing SequenceItems through a Sequencer to a Driver.
class MySequencer extends Sequencer<MySeqItem> {
  MySequencer(Component parent, {String name = 'mySequencer'})
      : super(name, parent);
}

// A Sequence is a modular object which has instructions for how to send
// SequenceItems to a Sequencer. A typical use case would be sending a
// collection of SequenceItems in a specific order.
class MySequence extends Sequence {
  //------------------------ Comment Out later ---------------------------
  final int numRepeat;

  MySequence(this.numRepeat, {String name = 'mySequence'}) : super(name);

  @override
  Future<void> body(Sequencer sequencer) async {
    final mySequencer = sequencer as MySequencer;
    for (var i = 0; i < numRepeat; i++) {
      mySequencer.add(MySeqItem(enable: true));
    }
  }
  //---------------------------------------------------------------------
}

/// A Driver is responsible for converting a SequenceItem into signal
/// transitions on a hardware interface. The driver accepts incoming items from
/// a Sequencer.
class MyDriver extends Driver<MySeqItem> {
  // Your interface
  final MyCounterInterface intf;

  // Keep a queue of items from the sequencer to be driven when desired
  final Queue<MySeqItem> _pendingItems = Queue<MySeqItem>();

  Objection? _driverObjection;

  MyDriver(this.intf, MySequencer sequencer, Component parent,
      {String name = 'counterDriver'})
      : super(name, parent, sequencer: sequencer);

  @override
  Future<void> run(Phase phase) async {
    unawaited(super.run(phase));

    // Listen to new items coming from the sequencer, and add them to a queue
    sequencer.stream.listen((newItem) {
      _driverObjection ??= phase.raiseObjection('my_driver')
        ..dropped.then((value) => logger.fine('Driver objection dropped'));
      _pendingItems.add(newItem);
    });

    // Every clock negative edge, drive the next pending item if it exists
    // Let user choose to drive at posedge or negedge
    intf.clk.negedge.listen((args) {
      if (_pendingItems.isNotEmpty) {
        final nextItem = _pendingItems.removeFirst();
        drive(nextItem);
        if (_pendingItems.isEmpty) {
          _driverObjection?.drop();
          _driverObjection = null;
        }
      }
    });
  }

  // Translate a SequenceItem into pin wiggles
  // use inject instead of put here
  void drive(MySeqItem? item) {
    if (item == null) {
      intf.en.inject(0);
    } else {
      intf.en.inject(item.en);
    }
  }
}

/// A Monitor is responsible for watching an interface and reporting out
/// interesting events onto an output stream. This bridges the hardware world
/// into an object that can be manipulated in the testbench. Many things can
/// listen to a Monitor, often logging or checking logic.
///
/// A monitor for the value output of the [MyCounter]].
class MyValueMonitor extends Monitor<LogicValue> {
  /// Instance of the [Interface] to the DUT.
  final MyCounterInterface intf;

  MyValueMonitor(this.intf, Component parent, {String name = 'myValueMonitor'})
      : super(name, parent);

  @override
  Future<void> run(Phase phase) async {
    unawaited(super.run(phase));

    // Every positive edge of the clock
    intf.clk.posedge.listen((event) {
      // Add the pin/port you want to monitor here.
      add(intf.val.value);
    });
  }
}

/// The Agent is a wrapper for related components, often which all look at a
/// single interface or set of interfaces. Typically, an Agent constructs
/// some Monitors, Drivers, and Sequencers, and then connects them up
/// appropriately to each other and interfaces.
class MyAgent extends Agent {
  final MyCounterInterface intf;
  late final MySequencer sequencer;
  late final MyDriver driver;
  late final MyValueMonitor valueMonitor;

  MyAgent(this.intf, Component parent, {String name = 'myAgent'})
      : super(name, parent) {
    sequencer = MySequencer(this);
    driver = MyDriver(intf, sequencer, this);
    valueMonitor = MyValueMonitor(intf, this);
  }
}

class MyScoreboard extends Component {
  /// A stream which sends out the current value out of the counter once per
  /// cycle.
  final Stream<LogicValue> valueStream;

  /// An instance of the interface to [MyCounter].
  final MyCounterInterface intf;

  MyScoreboard(this.valueStream, this.intf, Component parent,
      {String name = 'myScoreboard'})
      : super(name, parent);

  /// The most recent value received on [valueStream].
  int? _seenValue;

  /// The value seen last time from [valueStream].
  int _lastSeenValue = 0;

  @override
  Future<void> run(Phase phase) async {
    unawaited(super.run(phase));

    // record the value we saw this cycle
    valueStream.listen((event) {
      _seenValue = event.toInt();
    });

    // check values on negative edge
    intf.clk.negedge.listen((event) {
      if (intf.en.value == LogicValue.one) {
        int expected;

        // handle counter overflow
        if (_lastSeenValue == (1 << intf.width) - 1) {
          expected = 0;
        } else {
          expected = _lastSeenValue + 1;
        }

        final matchesExpectations = _seenValue == expected;

        if (!matchesExpectations) {
          logger.severe('Expected $expected but saw $_seenValue');
        } else {
          logger.finest('Counter value matches expectations with $_seenValue');
        }

        _lastSeenValue = _seenValue ?? 0;
      }
    });
  }
}

/// The Env is a wrapper for a collection of related components, often
/// each with their own hierarchy. Envs are usually composed of Agents,
/// scoreboards, configuration & coordination logic, other smaller Envs, etc.
class MyEnv extends Env {
  final MyCounterInterface intf;

  late final MyAgent agent;

  late final MyScoreboard scoreboard;

  MyEnv(this.intf, Component parent, {String name = 'myEnv'})
      : super(name, parent) {
    agent = MyAgent(intf, this);
    scoreboard = MyScoreboard(agent.valueMonitor.stream, intf, this);
  }

  @override
  Future<void> run(Phase phase) async {
    unawaited(super.run(phase));

    // Listen to the output of the monitor for some logging
    agent.valueMonitor.stream.listen((event) {
      logger.finer('Detected value on counter: $event');
    });
  }
}

class MyTest extends Test {
  // instantiate the DUT to test
  final MyCounter dut;

  // test environment for [dut].
  late final MyEnv env;

  // a private, local pointer to the test environment's [Sequencer].
  late final MySequencer _mySequencer;

  MyTest(this.dut, {String name = 'myTest'}) : super(name) {
    // instantiate the environment
    env = MyEnv(dut.counterintf, this);

    // point the sequencer to the agent's sequencer
    _mySequencer = env.agent.sequencer;
  }

  Future<void> waitNegedges(int numCycles) async {
    for (var i = 0; i < numCycles; i++) {
      await dut.clk.nextNegedge;
    }
  }

  @override
  Future<void> run(Phase phase) async {
    unawaited(super.run(phase));

    // Raise an objection at the start of the test so that the
    // simulation doesn't end before stimulus is injected
    final obj = phase.raiseObjection('my_test');

    logger.info('Running the test...');

    // Add some simple reset behavior at specified timestamps
    Simulator.registerAction(1, () {
      dut.counterintf.reset.put(0);
    });
    Simulator.registerAction(3, () {
      dut.counterintf.reset.put(1);
    });
    Simulator.registerAction(35, () {
      dut.counterintf.reset.put(0);
    });

    // Add an individual SequenceItem to set enable to 0 at the start
    _mySequencer.add(MySeqItem(enable: false));

    // Wait for the next negative edge of reset
    await dut.counterintf.reset.nextNegedge;

    // Wait 0 cycles
    await waitNegedges(0);

    // Kick off a sequence on the sequencer
    await _mySequencer.start(MySequence(5));

    logger.info('Done adding stimulus to the sequencer');

    // Done adding stimulus, we can drop our objection now
    obj.drop();
  }
}

Future<void> main({Level loggerLevel = Level.FINER}) async {
  // set the logger level
  Logger.root.level = loggerLevel;

  // create the testbench
  final tb = TopTB();

  // Build the DUT top level module
  await tb.counter.build();

  // dump wave here
  WaveDumper(tb.counter);

  // Set a maximum simulation time so it doesn't run forever
  Simulator.setMaxSimTime(300);

  // Create and start the test!
  final test = MyTest(tb.counter);
  await test.start();
}
