// Copyright (C) 2025-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_service_state.dart
// States for the ROHD service cubit.
//
// 2025 January 28
// Author: Roberto Torres <roberto.torres@intel.com>

part of 'rohd_service_cubit.dart';

/// Base state for ROHD service loading and error handling.
abstract class RohdServiceState extends Equatable {
  /// Creates a ROHD service state.
  const RohdServiceState();

  @override
  List<Object?> get props => [];
}

/// Initial state before any ROHD service activity occurs.
class RohdServiceInitial extends RohdServiceState {}

/// State emitted while loading ROHD service data.
class RohdServiceLoading extends RohdServiceState {}

/// State emitted after ROHD service data has been loaded.
class RohdServiceLoaded extends RohdServiceState {
  /// Loaded module tree data, if available.
  final TreeModel? treeModel;

  /// Creates a loaded state with tree data.
  const RohdServiceLoaded(this.treeModel);

  @override
  List<Object?> get props => [treeModel];
}

/// State emitted when ROHD service loading fails.
class RohdServiceError extends RohdServiceState {
  /// Error message.
  final String error;

  /// Stack trace associated with the failure.
  final StackTrace trace;

  /// Creates an error state.
  const RohdServiceError(this.error, this.trace);

  @override
  List<Object?> get props => [error, trace];
}
