// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// diagnostic_properties_test.dart
// Tests diagnostic properties exposed by public DevTools UI objects.
//
// 2026 July
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cubit/snapshot_cubit.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/tree_model.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/ui.dart';
import 'package:rohd_devtools_extension/rohd_devtools/view/tree_structure_page.dart';

void main() {
  test('public diagnostic objects expose at least one property', () {
    final vmServiceUriController = TextEditingController();
    final dtdUriController = TextEditingController();
    addTearDown(vmServiceUriController.dispose);
    addTearDown(dtdUriController.dispose);
    final module = TreeModel(
      name: 'top',
      inputs: const [],
      outputs: const [],
      subModules: const [],
    );
    final diagnosticObjects = <Diagnosticable>[
      const DetailsHelpButton(isDark: true),
      const DevtoolAppBar(),
      const DevToolsHelpButton(isDark: true),
      ModuleTreeCard(futureModuleTree: module),
      const ModuleTreeDetailsNavbar(),
      const PlatformIcon(Icons.waves, 'wave'),
      const SchematicIcon(),
      SignalDetailsCard(
        module: module,
        snapshot: const SnapshotLoaded(time: 0, signals: {}),
      ),
      SignalTable(
        selectedModule: module,
        searchTerm: '',
        inputSelectedVal: true,
        outputSelectedVal: true,
        inoutSelectedVal: true,
      ),
      SignalTableTextField(labelText: 'Signals', onChanged: (_) {}),
      VmConnectionForm(
        vmServiceUriController: vmServiceUriController,
        dtdUriController: dtdUriController,
        onConnect: () {},
        cleanVmServiceUri: (value) => value,
        cleanDtdUri: (value) => value,
      ),
      DiscoveredVmService(uri: 'ws://host:8181/app=/ws'),
      TreeStructurePage(screenSize: Size.zero),
    ];

    for (final object in diagnosticObjects) {
      expect(
        object.toDiagnosticsNode().getProperties(),
        isNotEmpty,
        reason: '${object.runtimeType} has no diagnostic properties',
      );
    }
  });
}
