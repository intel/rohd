// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// snapshot_cubit_test.dart
// Tests for signal snapshot cubit behavior.
//
// 2026 July
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cubit/snapshot_cubit.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/signal_value_source.dart';

class _FakeSignalValueSource implements SignalValueSource {
  _FakeSignalValueSource(this.snapshot);

  final SignalSnapshotData? snapshot;

  @override
  Stream<SignalValueUpdateEvent>? get updates => null;

  @override
  Future<int?> getCurrentTime() async => null;

  @override
  Future<SignalSnapshotData?> getSnapshot(int time) async => snapshot;
}

class _StreamingSignalValueSource extends _FakeSignalValueSource {
  _StreamingSignalValueSource(super.snapshot);

  final updatesController = StreamController<SignalValueUpdateEvent>();

  @override
  Stream<SignalValueUpdateEvent> get updates => updatesController.stream;

  Future<void> dispose() => updatesController.close();
}

class _ThrowingSignalValueSource implements SignalValueSource {
  @override
  Stream<SignalValueUpdateEvent>? get updates => null;

  @override
  Future<int?> getCurrentTime() async => null;

  @override
  Future<SignalSnapshotData?> getSnapshot(int time) =>
      Future<SignalSnapshotData?>.error(StateError('source unavailable'));
}

void main() {
  group('SnapshotCubit', () {
    test('maps source data into snapshots and supports both lookup methods',
        () async {
      final cubit = SnapshotCubit();
      addTearDown(cubit.close);
      final source = _FakeSignalValueSource({
        'top.counter': {
          'name': 'counter',
          'value': "8'h2a",
          'width': 8,
          'direction': 'output',
        },
        'top.internal': <String, dynamic>{},
      });

      final takingSnapshot = cubit.takeSnapshot(source, 42);
      expect(cubit.state, const SnapshotLoading(42));
      await takingSnapshot;

      final state = cubit.state as SnapshotLoaded;
      expect(state.time, 42);
      expect(
        state.getSignal('top.counter'),
        const SignalSnapshot(
          signalId: 'top.counter',
          name: 'counter',
          value: "8'h2a",
          width: 8,
          direction: 'output',
        ),
      );
      expect(state.getSignalByName('counter'),
          same(state.getSignal('top.counter')));
      expect(
        state.getSignal('top.internal'),
        const SignalSnapshot(
          signalId: 'top.internal',
          name: 'top.internal',
          value: '?',
          width: 1,
        ),
      );
      expect(state.getSignalByName('missing'), isNull);
    });

    test('reports an error when no snapshot data is available', () async {
      final cubit = SnapshotCubit();
      addTearDown(cubit.close);

      await cubit.takeSnapshot(_FakeSignalValueSource(null), 42);

      expect(cubit.state, const SnapshotError('No snapshot data returned'));
    });

    test('reports a source failure as an error state', () async {
      final cubit = SnapshotCubit();
      addTearDown(cubit.close);

      await cubit.takeSnapshot(_ThrowingSignalValueSource(), 42);

      expect(
        cubit.state,
        isA<SnapshotError>().having(
          (state) => state.message,
          'message',
          contains('source unavailable'),
        ),
      );
    });

    test('takes a snapshot for each video update containing data', () async {
      final cubit = SnapshotCubit();
      addTearDown(cubit.close);
      final source = _StreamingSignalValueSource({
        'top.counter': {'value': "8'h2a", 'width': 8},
      });
      addTearDown(source.dispose);

      cubit
        ..setMode(SignalTrackingMode.video)
        ..startVideoTracking(source);
      source.updatesController
        ..add(
          const SignalValueUpdateEvent(
            upToTime: 0,
            hasData: true,
            reason: 'initial',
          ),
        )
        ..add(
          const SignalValueUpdateEvent(
            upToTime: 17,
            hasData: true,
            reason: 'breakpoint',
          ),
        );

      await Future<void>.delayed(const Duration(milliseconds: 10));

      final state = cubit.state as SnapshotLoaded;
      expect(state.time, 17);
      expect(state.getSignal('top.counter')!.width, 8);
    });

    test('clear returns to camera mode and its initial state', () async {
      final cubit = SnapshotCubit();
      addTearDown(cubit.close);

      cubit
        ..setMode(SignalTrackingMode.video)
        ..clear();

      expect(cubit.mode, SignalTrackingMode.camera);
      expect(cubit.state, const SnapshotInitial());
    });
  });
}
