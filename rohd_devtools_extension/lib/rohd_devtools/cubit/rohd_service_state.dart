// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_service_state.dart
// States for the ROHD service cubit.
//
// 2025 January 28
// Author: Roberto Torres <roberto.torres@intel.com>

part of 'rohd_service_cubit.dart';

abstract class RohdServiceState extends Equatable {
  const RohdServiceState();

  @override
  List<Object?> get props => [];
}

class RohdServiceInitial extends RohdServiceState {}

class RohdServiceLoading extends RohdServiceState {}

class RohdServiceLoaded extends RohdServiceState {
  final TreeModel? treeModel;

  const RohdServiceLoaded(this.treeModel);

  @override
  List<Object?> get props => [treeModel];
}

class RohdServiceError extends RohdServiceState {
  final String error;
  final StackTrace trace;

  const RohdServiceError(this.error, this.trace);

  @override
  List<Object?> get props => [error, trace];
}
