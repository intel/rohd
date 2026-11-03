// Copyright (C) 2023-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// wire.dart
// Definition of underlying structure for storing information on a signal.
//
// 2023 May 26
// Author: Max Korbel <max.korbel@intel.com>

part of 'signals.dart';

/// Shares simulator lifecycle listeners among all [_Wire] instances.
///
/// The registry keeps only weak references to wires so discarded elaborations
/// cannot be retained by simulator-global stream subscriptions.
class _WireLifecycle {
  static final List<WeakReference<_Wire>> _wires = [];
  static final List<WeakReference<_Wire>> _changedWires = [];

  // Replaced and cancelled together when Simulator.reset replaces its streams.
  // ignore: cancel_subscriptions
  static StreamSubscription<void>? _preTickSubscription;
  // Replaced and cancelled together when Simulator.reset replaces its streams.
  // ignore: cancel_subscriptions
  static StreamSubscription<void>? _postTickSubscription;
  static bool _awaitingReset = false;

  /// Registers [wire] for pre-tick value snapshots.
  static void register(_Wire wire) {
    _wires.add(WeakReference(wire));
    _ensureSubscriptions();
  }

  /// Registers [wire] to emit changed events at the end of each tick.
  static void watchChanged(_Wire wire) {
    _changedWires.add(WeakReference(wire));
  }

  static void _ensureSubscriptions() {
    _preTickSubscription ??= Simulator.preTick.listen((_) {
      _forEachLiveWire(_wires, (wire) {
        wire._preTickValue = wire.value;
      });
    });
    _postTickSubscription ??= Simulator.postTick.listen((_) {
      _forEachLiveWire(_changedWires, (wire) {
        if (wire.value != wire._preTickValue && wire._preTickValue != null) {
          wire._changedController
              .add(LogicValueChanged(wire.value, wire._preTickValue!));
        }
      });
    });

    if (!_awaitingReset) {
      _awaitingReset = true;
      unawaited(Simulator.resetRequested.then((_) {
        _forEachLiveWire(_wires, (wire) {
          wire._preTickValue = wire.value;
        });

        final oldPreTickSubscription = _preTickSubscription;
        final oldPostTickSubscription = _postTickSubscription;
        _preTickSubscription = null;
        _postTickSubscription = null;
        _awaitingReset = false;

        unawaited(oldPreTickSubscription?.cancel());
        unawaited(oldPostTickSubscription?.cancel());
        _ensureSubscriptions();
      }));
    }
  }

  static void _forEachLiveWire(
    List<WeakReference<_Wire>> references,
    void Function(_Wire wire) action,
  ) {
    final liveWires = <_Wire>[];
    references.removeWhere((reference) {
      final wire = reference.target;
      if (wire == null || !wire._lifecycleActive) {
        return true;
      }

      liveWires.add(wire);
      return false;
    });

    liveWires.forEach(action);
  }
}

/// Represents a physical wire which shares a common value with one or
/// more [Logic]s.
class _Wire {
  _Wire({required this.width})
      : _currentValue = LogicValue.filled(width, LogicValue.z) {
    _WireLifecycle.register(this);
  }

  /// The current active value of this signal.
  LogicValue get value => _currentValue;

  /// The number of bits in this signal.
  final int width;

  /// The current active value of this signal.
  LogicValue _currentValue;

  /// The [Logic] whose immutability makes this wire immutable.
  Logic? _immutableOwner;

  /// Additional context explaining why this wire is immutable.
  String? _immutableReason;

  /// Makes this wire immutable on behalf of [owner].
  ///
  /// If this wire is already immutable, the original owner and reason are
  /// preserved.
  void makeImmutable(Logic owner, {String? reason}) {
    _immutableOwner ??= owner;
    _immutableReason ??= reason;
  }

  /// Throws an [UnassignableException] if this wire is immutable, identifying
  /// [signalName] as the signal through which the update was attempted.
  void _assertMutable({required String signalName}) {
    final immutableOwner = _immutableOwner;
    if (immutableOwner != null) {
      final attemptedUpdateReason =
          'Signal "$signalName" cannot be updated because it is driven by '
          'immutable signal "$immutableOwner".';
      throw UnassignableException(
        immutableOwner,
        reason: [
          attemptedUpdateReason,
          if (_immutableReason != null) _immutableReason,
        ].join(' '),
      );
    }
  }

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
  ///
  /// The controller remains open after wire adoption so existing listeners
  /// continue receiving forwarded [changed] events from the adopted wire.
  // ignore: close_sinks
  final StreamController<LogicValueChanged> _changedController =
      StreamController<LogicValueChanged>.broadcast(sync: true);

  /// Tracks whether is being subscribed to by anything/anyone.
  bool _changedBeingWatched = false;

  /// A [Stream] of [LogicValueChanged] events which triggers at most once
  /// per [Simulator] tick, iff the value of the [Logic] has changed.
  Stream<LogicValueChanged> get changed {
    if (!_changedBeingWatched) {
      _changedBeingWatched = true;
      _WireLifecycle.watchChanged(this);
    }
    return _changedController.stream;
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

  /// Whether this wire should receive simulator lifecycle updates.
  bool _lifecycleActive = true;

  /// Stops lifecycle updates and uses [other]'s [changed] as the source to
  /// replace all [changed] events for this [_Wire].
  void _migrateChangedTriggers(_Wire other) {
    _lifecycleActive = false;

    if (_changedBeingWatched) {
      other.changed.listen(_changedController.add);
      _changedBeingWatched = false;
    }
  }

  /// Rejects constraint adoption that would change this immutable wire's value.
  void _assertCanAdopt(_Wire other, {required String signalName}) {
    if (_immutableOwner == null || other._valueConstraints.isEmpty) {
      return;
    }

    var constrainedValue = value;
    for (final constraint in {
      ..._valueConstraints,
      ...other._valueConstraints
    }) {
      constrainedValue = constraint(constrainedValue);
    }
    if (constrainedValue != value) {
      _assertMutable(signalName: signalName);
    }
  }

  /// Tells this [_Wire] to adopt all the behavior of [other] so that
  /// it can replace [other]. Returns the [_Wire] that has adopted everything.
  _Wire _adopt(_Wire other) {
    if (_immutableOwner == null && other._immutableOwner != null) {
      _immutableOwner = other._immutableOwner;
      _immutableReason = other._immutableReason;
    }

    _glitchController.emitter.adopt(other._glitchController.emitter);
    other._migrateChangedTriggers(this);
    _valueConstraints.addAll(other._valueConstraints);

    // ignore: avoid_returning_this - this is overriding a function that sometimes returns not this
    return this;
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
    _assertMutable(signalName: signalName);
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
  /// This function is used for propagating glitches through connected signals.
  /// Use this function for custom definitions of [Module] behavior.
  void put(dynamic val, {required String signalName, bool fill = false}) {
    _assertMutable(signalName: signalName);

    var newValue = LogicValue.of(val, fill: fill, width: width);

    if (newValue.width != width) {
      throw PutException(signalName,
          'Updated value width mismatch. The width of $val should be $width.');
    }

    if (_isPutting) {
      // if this is the result of a cycle, then contention!
      newValue = LogicValue.filled(width, LogicValue.x);
    }

    _updateValue(_applyValueConstraints(newValue), signalName: signalName);
  }

  /// Distinct value transformations applied in registration order before an
  /// update.
  final Set<_LogicValueConstraint> _valueConstraints = {};

  /// Applies constraints without writing a value or emitting events.
  LogicValue _applyValueConstraints(LogicValue value) {
    for (final constraint in _valueConstraints) {
      value = constraint(value);
    }
    return value;
  }

  /// Adds a transformation that constrains every value written to this wire.
  void _constrainValue(_LogicValueConstraint constraint) {
    _valueConstraints.add(constraint);
  }

  /// Updates the value of this signal to [newValue].
  void _updateValue(LogicValue newValue, {required String signalName}) {
    final prevValue = value;

    _currentValue = newValue;

    // sends out a glitch if the value deposited has changed
    if (value != prevValue) {
      _isPutting = true;
      _glitchController.add(LogicValueChanged(value, prevValue));
      _isPutting = false;
    }
  }

  @override
  String toString() => 'wire $hashCode';
}

/// Transforms a proposed wire value into the value that may be stored.
typedef _LogicValueConstraint = LogicValue Function(LogicValue origValue);
