// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// standalone_rohd_service_state.dart
// States for standalone ROHD service.
//
// 2026 January
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

part of 'standalone_rohd_service_cubit.dart';

/// Abstract base class for standalone ROHD service states.
sealed class StandaloneRohdServiceState extends Equatable {
  const StandaloneRohdServiceState();

  @override
  List<Object?> get props => [];
}

/// Initial state when the service is not yet connected.
class StandaloneRohdServiceInitial extends StandaloneRohdServiceState {}

/// Loading state when the module tree is being evaluated.
class StandaloneRohdServiceLoading extends StandaloneRohdServiceState {}

/// Loaded state when the module tree has been successfully evaluated.
class StandaloneRohdServiceLoaded extends StandaloneRohdServiceState {
  /// The evaluated module tree model.
  final TreeModel? treeModel;

  /// Constructor for [StandaloneRohdServiceLoaded].
  const StandaloneRohdServiceLoaded(this.treeModel);

  @override
  List<Object?> get props => [treeModel];
}

/// Error state when there was an issue connecting or evaluating the module
/// tree.
class StandaloneRohdServiceError extends StandaloneRohdServiceState {
  /// The error message.
  final String error;

  /// The stack trace of the error.
  final StackTrace? trace;

  /// Constructor for [StandaloneRohdServiceError].
  const StandaloneRohdServiceError(this.error, [this.trace]);

  @override
  List<Object?> get props => [error, trace];
}
