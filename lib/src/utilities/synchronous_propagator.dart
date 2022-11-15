/// Copyright (C) 2021 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// synchronous_propogator.dart
/// Ultra light-weight events for signal propogation
///
/// 2021 August 3
/// Author: Max Korbel <max.korbel@intel.com>
///

/***/

/// A controller for a [SynchronousEmitter] that allows for
/// adding of events of type [T] to be emitted.
class SynchronousPropagator<T> {
  /// The [SynchronousEmitter] which sends events added to this.
  SynchronousEmitter<T> get emitter => _emitter;
  final SynchronousEmitter<T> _emitter = SynchronousEmitter<T>();

  /// When set to `true`, will throw an exception if an event
  /// added is reentrant.
  bool throwOnReentrance = false;

  /// Adds a new event [t] to be emitted from [emitter].
  void add(T t) {
    if (throwOnReentrance && _emitter.isEmitting) {
      throw Exception('Disallowed reentrance occurred.');
    }
    _emitter._propagate(t);
  }
}

/// A stream of events of type [T] that can be synchronously listened to.
class SynchronousEmitter<T> {
  /// Registers a new listener [f] to be notified with an event of
  /// type [T] as an argument whenever that event is to be emitted.
  void listen(void Function(T args) f) => _actions.add(f);

  /// A [List] of actions to perform for each event.
  final List<void Function(T)> _actions = <void Function(T)>[];

  /// Returns `true` iff this is currently emitting.
  ///
  /// Useful for reentrance checking.
  bool get isEmitting => _isEmitting;
  bool _isEmitting = false;

  /// Sends out [t] to all listeners.
  void _propagate(T t) {
    _isEmitting = true;
    for (final action in _actions) {
      action(t);
    }
    _isEmitting = false;
  }

  /// Tells this emitter to adopt all behavior of [other].
  ///
  /// Tells this emitter to perform all the actions of [other] each
  /// time this would propagate.  Also clears all actions from [other]
  /// so that it will not execute anything in the future.
  void adopt(SynchronousEmitter<T> other) {
    _actions.addAll(other._actions);
    other._actions.clear();
  }
}
