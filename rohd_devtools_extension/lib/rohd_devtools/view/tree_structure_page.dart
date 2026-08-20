// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// tree_structure_page.dart
// Page for the tree structure.
//
// 2024 January 5
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cubit/cubits.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/ui.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart';

/// Split-pane page showing the module tree and selected module details.
class TreeStructurePage extends StatelessWidget {
  /// Creates the tree structure page.
  TreeStructurePage({required this.screenSize, super.key});

  /// Available size used to split the page into two panes.
  final Size screenSize;

  /// Horizontal scroll controller for the tree pane.
  final ScrollController _horizontal = ScrollController();

  /// Vertical scroll controller for the tree pane.
  final ScrollController _vertical = ScrollController();

  /// Boundary used when exporting the tree pane as PNG.
  final GlobalKey _treeBoundaryKey = GlobalKey();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<Size>('screenSize', screenSize));
  }

  @override

  /// Builds the split-pane tree structure page.
  Widget build(BuildContext context) => MultiBlocListener(
          listeners: [
            BlocListener<RohdServiceCubit, RohdServiceState>(
                listener: (context, state) {
              final snapshotCubit = context.read<SnapshotCubit>();

              if (state is RohdServiceLoaded) {
                final source =
                    context.read<RohdServiceCubit>().signalValueSource;
                if (source == null) {
                  return;
                }

                if (snapshotCubit.mode != SignalTrackingMode.video) {
                  snapshotCubit.setMode(SignalTrackingMode.video);
                }

                snapshotCubit.startVideoTracking(source);
              } else if (state is RohdServiceInitial ||
                  state is RohdServiceError) {
                snapshotCubit.clear();
              }
            })
          ],
          child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildTreePane(context),
                        _buildDetailsPane(context)
                      ]))));

  Widget _buildTreePane(BuildContext context) => SizedBox(
      width: screenSize.width / 2,
      child: Card(
          clipBehavior: Clip.antiAlias,
          child: Stack(children: [
            RepaintBoundary(
                key: _treeBoundaryKey,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTreeToolbar(context),
                      Expanded(
                          child: Scrollbar(
                              thumbVisibility: true,
                              controller: _vertical,
                              child: SingleChildScrollView(
                                  controller: _vertical,
                                  child: Row(children: [
                                    Expanded(
                                        child: Scrollbar(
                                            thumbVisibility: true,
                                            controller: _horizontal,
                                            child: SingleChildScrollView(
                                                scrollDirection:
                                                    Axis.horizontal,
                                                controller: _horizontal,
                                                child: BlocBuilder<
                                                        RohdServiceCubit,
                                                        RohdServiceState>(
                                                    builder: (context, state) =>
                                                        _buildTreeStateBody(
                                                            state)))))
                                  ]))))
                    ])),
            Positioned(
                right: 8,
                bottom: 8,
                child: ExportPngButton(
                    onPressed: () => captureBoundaryToPng(context,
                        boundaryKey: _treeBoundaryKey,
                        filePrefix: 'module_tree')))
          ])));

  Widget _buildTreeToolbar(BuildContext context) => Padding(
      padding: const EdgeInsets.all(10),
      child: Row(children: [
        const Icon(Icons.account_tree),
        const SizedBox(width: 10),
        const Text('Module Tree'),
        Expanded(
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          SizedBox(
              width: 200,
              child: TextField(
                  onChanged: (value) {
                    context.read<TreeSearchTermCubit>().setTerm(value);
                  },
                  decoration: const InputDecoration(labelText: 'Search Tree'))),
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () =>
                  context.read<RohdServiceCubit>().evalModuleTree())
        ]))
      ]));

  Widget _buildTreeStateBody(RohdServiceState state) {
    if (state is RohdServiceLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state is RohdServiceLoaded) {
      final futureModuleTree = state.treeModel;
      if (futureModuleTree == null) {
        return Container(
            padding: const EdgeInsets.all(20),
            child: const Text(
                'Friendly Notice: Please make sure that you use build() '
                'method to build your module and put the breakpoint at '
                'the simulation time.',
                style: TextStyle(fontSize: 20),
                textAlign: TextAlign.center));
      }

      return ModuleTreeCard(futureModuleTree: futureModuleTree);
    }

    if (state is RohdServiceError) {
      return Center(child: Text('Error: ${state.error}'));
    }

    return const Center(child: Text('Unknown state'));
  }

  Widget _buildDetailsPane(BuildContext context) => SizedBox(
      width: screenSize.width / 2,
      child: Card(
          clipBehavior: Clip.antiAlias,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const ModuleTreeDetailsNavbar(),
            Expanded(
                child: BlocBuilder<DetailsTabCubit, DetailsTab>(
                    builder: (context, selectedTab) =>
                        IndexedStack(index: selectedTab.index, children: [
                          Padding(
                              padding:
                                  const EdgeInsets.only(left: 20, right: 20),
                              child: BlocBuilder<SelectedModuleCubit,
                                      SelectedModuleState>(
                                  builder: (context, state) =>
                                      BlocBuilder<SnapshotCubit, SnapshotState>(
                                          builder: (context, snapshotState) {
                                        if (state is SelectedModuleLoaded) {
                                          return SignalDetailsCard(
                                              module: state.module,
                                              snapshot: snapshotState
                                                      is SnapshotLoaded
                                                  ? snapshotState
                                                  : null);
                                        }

                                        return const Center(
                                            child: Text('No module selected'));
                                      }))),
                          _buildFeaturePlaceholderPane(context,
                              icon: platformIcon(Icons.waves, '🌊',
                                  size: 36,
                                  color: Theme.of(context).colorScheme.primary,
                                  hasColorEmoji: kIsWeb),
                              title: 'Waveform',
                              message: 'Waveform content will be available '
                                  'in a future release.'),
                          _buildFeaturePlaceholderPane(context,
                              icon: const SchematicIcon(size: 36),
                              title: 'Schematic',
                              message: 'Schematic content will be available '
                                  'in a future release.')
                        ])))
          ])));

  Widget _buildFeaturePlaceholderPane(BuildContext context,
      {required Widget icon, required String title, required String message}) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
        child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  icon,
                  const SizedBox(height: 12),
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: colorScheme.onSurface.withValues(alpha: 0.72)))
                ]))));
  }
}
