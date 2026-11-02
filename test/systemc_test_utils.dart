// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// systemc_test_utils.dart
// Shared SystemC test-environment helpers.
//
// 2026 November 2
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:io';

/// The reason for skipping optional SystemC integration tests locally.
const systemCUnavailableMessage = 'SystemC headers and library were not found.';

/// Whether this process must fail when SystemC is unavailable.
bool get systemCIsRequired =>
    Platform.environment['ROHD_REQUIRE_SYSTEMC'] == '1';

/// Whether the SystemC comparison utilities can find a supported installation.
bool get hasSystemCInstallation {
  for (final (include, lib) in [
    ('/opt/systemc/include', '/opt/systemc/lib'),
    ('/usr/include', '/usr/lib/x86_64-linux-gnu'),
  ]) {
    if (File('$include/systemc.h').existsSync() &&
        File('$lib/libsystemc.so').existsSync()) {
      return true;
    }
  }
  return false;
}

/// A test `skip` value for integration tests that need a real SystemC runtime.
///
/// CI sets `ROHD_REQUIRE_SYSTEMC=1`, so a missing installation remains a
/// failure there instead of silently skipping coverage.
Object get systemCIntegrationSkip => hasSystemCInstallation || systemCIsRequired
    ? false
    : systemCUnavailableMessage;
