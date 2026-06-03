// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_devtools_observer.dart
// Bloc observer for the app.
//
// 2025 January 28
// Author: Roberto Torres <roberto.torres@intel.com>

import 'package:flutter_bloc/flutter_bloc.dart';

/// [BlocObserver] observe all state changes in the application.
class RohdDevToolsObserver extends BlocObserver {
  /// Creates the observer used by the app.
  const RohdDevToolsObserver();

  @override

  /// Forwards bloc state changes to the default observer behavior.
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    super.onChange(bloc, change);
  }
}
