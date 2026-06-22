// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// module_tree_details_navbar.dart
// UI for module tree details card navrbar.
//
// 2024 January 5
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cubit/cubits.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/details_help_button.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/platform_icon.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/schematic_icon.dart';

/// Navigation bar for switching between module detail views.
class ModuleTreeDetailsNavbar extends StatelessWidget {
  /// Whether color emoji fonts are available on this platform.
  final bool hasColorEmoji;

  /// Creates the details navigation bar.
  const ModuleTreeDetailsNavbar({super.key, this.hasColorEmoji = kIsWeb});

  @override

  /// Adds diagnostic properties for the nav bar.
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(FlagProperty('hasColorEmoji',
        value: hasColorEmoji, ifFalse: 'using fallback emojis'));
  }

  @override

  /// Builds the tab row and help button for module details.
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DecoratedBox(
        decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            border: Border(
                bottom: BorderSide(color: Theme.of(context).dividerColor))),
        child: BlocBuilder<DetailsTabCubit, DetailsTab>(
            builder: (context, selectedTab) => Row(children: [
                  _TabButton(
                      label: 'Details',
                      icon: platformIcon(Icons.info, 'ℹ️',
                          size: 18, hasColorEmoji: hasColorEmoji),
                      isSelected: selectedTab == DetailsTab.details,
                      onTap: () => context
                          .read<DetailsTabCubit>()
                          .selectTab(DetailsTab.details)),
                  _TabButton(
                      label: 'Waveform',
                      icon: platformIcon(Icons.waves, '🌊',
                          size: 18, hasColorEmoji: hasColorEmoji),
                      isSelected: selectedTab == DetailsTab.waveform,
                      onTap: () => context
                          .read<DetailsTabCubit>()
                          .selectTab(DetailsTab.waveform)),
                  _TabButton(
                      label: 'Schematic',
                      icon: const SchematicIcon(size: 18),
                      isSelected: selectedTab == DetailsTab.schematic,
                      onTap: () => context
                          .read<DetailsTabCubit>()
                          .selectTab(DetailsTab.schematic)),
                  const Spacer(),
                  DetailsHelpButton(isDark: isDark)
                ])));
  }
}

class _TabButton extends StatelessWidget {
  /// The tab text label.
  final String label;

  /// Icon shown next to the label.
  final Widget icon;

  /// Whether this tab is currently selected.
  final bool isSelected;

  /// Callback invoked when the tab is tapped.
  final VoidCallback onTap;

  const _TabButton(
      {required this.label,
      required this.icon,
      required this.isSelected,
      required this.onTap});

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(StringProperty('label', label))
      ..add(DiagnosticsProperty<Widget>('icon', icon))
      ..add(FlagProperty('isSelected', value: isSelected))
      ..add(
          ObjectFlagProperty<VoidCallback>('onTap', onTap, ifNull: 'disabled'));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selectedColor = colorScheme.primary;
    final unselectedColor = colorScheme.onSurface.withValues(alpha: 0.6);

    return InkWell(
        onTap: onTap,
        child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(
                        color: isSelected ? selectedColor : Colors.transparent,
                        width: 2))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              icon,
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? selectedColor : unselectedColor))
            ])));
  }
}
