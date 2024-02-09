// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// wire.dart
// Definition of underlying structure for storing information on a signal.
//
// 2023 May 26
// Author: Max Korbel <max.korbel@intel.com>

part of 'signals.dart';

/// Represents a physical wire which shares a common value with one or
/// more [Logic]s.
class _Wire {
  _Wire({required this.width})
      : _currentValue = LogicValue.filled(width, LogicValue.z) {
    _setupPreTickListener();
  }

  /// The current active value of this signal.
  LogicValue get value => _currentValue;

  /// The number of bits in this signal.
  final int width;

  /// The current active value of this signal.
  LogicValue _currentValue;

  /// The last value of this signal before the [Simulator] tick.
  ///
  /// This is useful for detecting when to trigger an edge.
  LogicValue? _preTickValue;

  /// A stream of [LogicValueChanged] events for every time the signal
  /// transitions at any time during a [Simulator] tick.
  ///
  /// This event can occur more than once per edge, or even if there is no edge.
  SynchronousEmitter<LogicValueChanged> get glitch => _glitchController.emitter;
  final SynchronousPropagator<LogicValueChanged> _glitchController =
      SynchronousPropagator<LogicValueChanged>();

  /// Controller for stable events that can be safely consumed at the
  /// end of a [Simulator] tick.
  final StreamController<LogicValueChanged> _changedController =
      StreamController<LogicValueChanged>.broadcast(sync: true);

  /// Tracks whether is being subscribed to by anything/anyone.
  bool _changedBeingWatched = false;

  /// A [Stream] of [LogicValueChanged] events which triggers at most once
  /// per [Simulator] tick, iff the value of the [Logic] has changed.
  Stream<LogicValueChanged> get changed {
    if (!_changedBeingWatched) {
      // only do these simulator subscriptions if someone has asked for
      // them! saves performance!
      _changedBeingWatched = true;

      StreamSubscription<void> subscribe() {
        unawaited(Simulator.resetRequested.then((_) async {
          final oldPostTickSubscription = _postTickSubscription;

          _postTickSubscription = subscribe();

          unawaited(oldPostTickSubscription?.cancel());
        }));

        return Simulator.postTick.listen((event) {
          if (value != _preTickValue && _preTickValue != null) {
            _changedController.add(LogicValueChanged(value, _preTickValue!));
          }
        });
      }

      assert(_postTickSubscription == null,
          'Should not be creating a new subscription if one exists.');

      _postTickSubscription = subscribe();
    }
    return _changedController.stream;
  }

  /// Sets up the pre-tick listener for [_preTickValue].
  ///
  /// If one already exists, it will not create a new one.
  void _setupPreTickListener() {
    _preTickSubscription = Simulator.preTick.listen((event) {
      _preTickValue = value;
    });

    unawaited(Simulator.resetRequested.then((_) async {
      assert(_preTickSubscription != null,
          'Should not be null if we are setting up a new one.');

      _preTickValue = value;

      final oldPreTickSubscription = _preTickSubscription;

      _setupPreTickListener();

      unawaited(oldPreTickSubscription?.cancel());
    }));
  }

  /// The [value] of this signal before the most recent [Simulator.tick] had
  /// completed. It will be `null` before the first tick after this signal is
  /// created.
  ///
  /// If this is called mid-tick, it will be the value from before the tick
  /// started. If this is called post-tick, it will be the value from before
  /// that last tick started.
  ///
  /// This is useful for querying the value of a signal in a testbench before
  /// some change event occurred, for example sampling a signal before a clock
  /// edge for code that was triggered on that edge.
  ///
  /// Note that if a signal is connected to another signal, the listener may
  /// be reset.
  LogicValue? get previousValue => _preTickValue;

  /// The subscription to the [Simulator]'s `preTick`.
  ///
  /// Non-null after the first tick has occurred after creation of `this`.
  StreamSubscription<void>? _preTickSubscription;

  /// The subscription to the [Simulator]'s `postTick`.
  ///
  /// Only non-null if [_changedBeingWatched] is true.
  StreamSubscription<void>? _postTickSubscription;

  /// Cancels all [Simulator] subscriptions and uses [other]'s [changed] as the
  /// source to replace all [changed] events for this [_Wire].
  void _migrateChangedTriggers(_Wire other) {
    unawaited(_preTickSubscription?.cancel());

    if (_changedBeingWatched) {
      final newChanged = other.changed;
      unawaited(_postTickSubscription?.cancel());
      newChanged.listen(_changedController.add);
      _changedBeingWatched = false;
    }
  }

  /// Tells this [_Wire] to adopt all the behavior of [other] so that
  /// it can replace [other].
  void _adopt(_Wire other) {
    _glitchController.emitter.adopt(other._glitchController.emitter);
    other._migrateChangedTriggers(this);
  }

  /// Store the [negedge] stream to avoid creating multiple copies
  /// of streams.
  Stream<LogicValueChanged>? _negedge;

  /// Store the [posedge] stream to avoid creating multiple copies
  /// of streams.
  Stream<LogicValueChanged>? _posedge;

  /// A [Stream] of [LogicValueChanged] events which triggers at most once
  /// per [Simulator] tick, iff the value of the [Logic] has changed
  /// from `1` to `0`.
  ///
  /// Throws an exception if [width] is not `1`.
  Stream<LogicValueChanged> get negedge {
    if (width != 1) {
      throw Exception(
          'Can only detect negedge when width is 1, but was $width');
    }

    _negedge ??= changed.where((args) => LogicValue.isNegedge(
          args.previousValue,
          args.newValue,
          ignoreInvalid: true,
        ));

    return _negedge!;
  }

  /// A [Stream] of [LogicValueChanged] events which triggers at most once
  /// per [Simulator] tick, iff the value of the [Logic] has changed
  /// from `0` to `1`.
  ///
  /// Throws an exception if [width] is not `1`.
  Stream<LogicValueChanged> get posedge {
    if (width != 1) {
      throw Exception(
          'Can only detect posedge when width is 1, but was $width');
    }

    _posedge ??= changed.where((args) => LogicValue.isPosedge(
          args.previousValue,
          args.newValue,
          ignoreInvalid: true,
        ));

    return _posedge!;
  }

  /// Triggers at most once, the next time that this [Logic] changes
  /// value at the end of a [Simulator] tick.
  Future<LogicValueChanged> get nextChanged => changed.first;

  /// Triggers at most once, the next time that this [Logic] changes
  /// value at the end of a [Simulator] tick from `0` to `1`.
  ///
  /// Throws an exception if [width] is not `1`.
  Future<LogicValueChanged> get nextPosedge => posedge.first;

  /// Triggers at most once, the next time that this [Logic] changes
  /// value at the end of a [Simulator] tick from `1` to `0`.
  ///
  /// Throws an exception if [width] is not `1`.
  Future<LogicValueChanged> get nextNegedge => negedge.first;

  /// Injects a value onto this signal in the current [Simulator] tick.
  ///
  /// This function calls [put()] in [Simulator.injectAction()].
  void inject(dynamic val, {required String signalName, bool fill = false}) {
    Simulator.injectAction(() => put(val, signalName: signalName, fill: fill));
  }

  /// Keeps track of whether there is an active put, to detect reentrance.
  bool _isPutting = false;

  /// Puts a value [val] onto this signal, which may or may not be picked up
  /// for [changed] in this [Simulator] tick.
  ///
  /// The type of [val] and usage of [fill] should be supported by
  /// [LogicValue.of].
  ///
  /// This function is used for propogating glitches through connected signals.
  /// Use this function for custom definitions of [Module] behavior.
  void put(dynamic val, {required String signalName, bool fill = false}) {
    var newValue = LogicValue.of(val, fill: fill, width: width);

    if (newValue.width != width) {
      throw PutException(signalName,
          'Updated value width mismatch. The width of $val should be $width.');
    }

    if (_isPutting) {
      // if this is the result of a cycle, then contention!
      newValue = LogicValue.filled(width, LogicValue.x);
    }

    final prevValue = _currentValue;
    _currentValue = newValue;

    // sends out a glitch if the value deposited has changed
    if (_currentValue != prevValue) {
      _isPutting = true;
      _glitchController.add(LogicValueChanged(_currentValue, prevValue));
      _isPutting = false;
    }
  }
}
