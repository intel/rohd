/// Copyright (C) 2021 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
/// 
/// synchronous_propogator.dart
/// Ultra light-weight events for signal propogation
/// 
/// 2021 August 3
/// Author: Max Korbel <max.korbel@intel.com>
/// 

//TODO: does this need reentrance detection?

class SynchronousPropagator<T> {
  final SynchronousEmitter<T> _emitter = SynchronousEmitter<T>();
  SynchronousEmitter<T> get emitter => _emitter;
  void add(T t) => _emitter._propogate(t);
}

class SynchronousEmitter<T> {
  final List<Function(T)> _actions = <Function(T)>[];
  void listen(Function(T args) f) => _actions.add(f);
  void _propogate(T t) {
    for(var action in _actions) {
      action(t);
    }
  }
}