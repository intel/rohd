// Copyright (C) 2025-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// logic_def.dart
// Definition for LogicDef.
//
// 2026 July 22
// Author: Max Korbel <max.korbel@intel.com>

part of 'signals.dart';

@internal
sealed class LogicDef extends Logic {
  final bool reserveDefinitionName;

  String get definitionName => _definitionName;
  final String _definitionName;

  LogicDef({
    required String definitionName,
    super.width,
    super.name,
    super.naming,
    this.reserveDefinitionName = false,
  }) : _definitionName = Sanitizer.sanitizeSV(Naming.validatedName(
          definitionName,
          reserveName: reserveDefinitionName,
        )!);
}
