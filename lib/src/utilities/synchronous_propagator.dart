// Copyright (C) 2021-2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// synchronous_propogator.dart
// Ultra light-weight events for signal propogation
//
// 2021 August 3
// Author: Max Korbel <max.korbel@intel.com>
//

import 'dart:async';
import 'dart:collection';

import 'package:rohd/src/collections/iterable_removable_queue.dart';

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
  ///
  /// Returns a [SynchronousSubscription] representing this listener which can
  /// be cancelled.
  SynchronousSubscription<T> listen(void Function(T args) f) {
    final subscription = SynchronousSubscription<T>(f);
    _subscriptions.add(subscription);
    return subscription;
  }

  /// A [List] of actions to perform for each event.
  final IterableRemovableQueue<SynchronousSubscription<T>> _subscriptions =
      IterableRemovableQueue<SynchronousSubscription<T>>();

  /// Returns `true` iff this is currently emitting.
  ///
  /// Useful for reentrance checking.
  bool get isEmitting => _isEmitting;
  bool _isEmitting = false;

  /// Determines whether a [SynchronousSubscription] should be removed from the
  /// collection of active [_subscriptions].
  static bool _doRemove<T>(SynchronousSubscription<T> subscription) =>
      subscription._cancelled;

  /// Sends out [t] to all listeners.
  void _propagate(T t) {
    _isEmitting = true;

    _subscriptions.iterate(
      action: (subscription) => subscription.func(t),
      removeWhere: _doRemove,
    );

    _isEmitting = false;
  }

  /// Tells this emitter to adopt all behavior of [other].
  ///
  /// Tells this emitter to perform all the actions of [other] each
  /// time this would propagate.  Also clears all actions from [other]
  /// so that it will not execute anything in the future.
  void adopt(SynchronousEmitter<T> other) {
    _subscriptions.takeAll(other._subscriptions);
  }
}

/// Represents a subscription generated by listening to a [SynchronousEmitter].
class SynchronousSubscription<T> {
  /// The [Function] to execute when this subscription is triggered by an event.
  final void Function(T args) func;

  /// If true, then this subscription is actively triggering [func] on the
  /// registered event.
  bool get isActive => !_cancelled;

  /// Keeps track of whether this subscription has been cancelled.
  bool _cancelled = false;

  /// Constructs a new subscription so that [func] executes on certain events.
  SynchronousSubscription(this.func);

  /// Cancels the subscription, so that [func] will no longer be called when
  /// the listened-to event occurs.
  ///
  /// Calling this will make [isActive] `false`.
  void cancel() {
    _cancelled = true;
  }
}
