// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// module_tree_details_navbar.dart
// UI for module tree details card navbar.
//
// 2024 January 5
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cubit/cubits.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/details_help_button.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/platform_icon.dart';
import 'package:rohd_schematic_viewer/schematic_viewer.dart';
import 'package:rohd_wave_viewer/rohd_wave_viewer.dart';

/// Navbar for switching between detail tabs.
///
/// Uses platform icons with emoji fallback for consistent appearance.
class ModuleTreeDetailsNavbar extends StatelessWidget {
  /// Whether the platform supports color emoji.
  /// Defaults to true (works for web). On Linux, check with
  /// `isEmojiFontInstalled`.
  final bool hasColorEmoji;

  /// Constructor for [ModuleTreeDetailsNavbar].
  const ModuleTreeDetailsNavbar({super.key, this.hasColorEmoji = true});

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      FlagProperty(
        'hasColorEmoji',
        value: hasColorEmoji,
        ifFalse: 'using fallback emojis',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: BlocBuilder<DetailsTabCubit, DetailsTab>(
        builder: (context, selectedTab) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return Row(
            children: [
              _TabButton(
                label: 'Details',
                icon: platformIcon(
                  Icons.info,
                  'ℹ️',
                  size: 18,
                  hasColorEmoji: hasColorEmoji,
                ),
                isSelected: selectedTab == DetailsTab.details,
                onTap: () => context.read<DetailsTabCubit>().selectTab(
                      DetailsTab.details,
                    ),
              ),
              _TabButton(
                label: 'Waveform',
                icon: platformIcon(
                  Icons.waves,
                  '🌊',
                  size: 18,
                  hasColorEmoji: hasColorEmoji,
                ),
                isSelected: selectedTab == DetailsTab.waveform,
                onTap: () => context.read<DetailsTabCubit>().selectTab(
                      DetailsTab.waveform,
                    ),
              ),
              _TabButton(
                label: 'Schematic',
                icon: const SchematicIcon(size: 18),
                isSelected: selectedTab == DetailsTab.schematic,
                onTap: () => context.read<DetailsTabCubit>().selectTab(
                      DetailsTab.schematic,
                    ),
              ),
              const Spacer(),
              _tabHelpButton(selectedTab, isDark: isDark),
            ],
          );
        },
      ),
    );
  }

  /// Returns the help button matching the currently selected tab.
  static Widget _tabHelpButton(DetailsTab tab, {required bool isDark}) {
    switch (tab) {
      case DetailsTab.waveform:
        return WaveViewerHelpButton(isDark: isDark);
      case DetailsTab.schematic:
        return SchematicHelpButton(isDark: isDark);
      case DetailsTab.details:
        return DetailsHelpButton(isDark: isDark);
    }
  }
}

/// Individual tab button - uses InkWell for hover feedback.
/// The RepaintBoundary at the Scaffold level prevents full app redraws.
class _TabButton extends StatelessWidget {
  final String label;
  final Widget icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _TabButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(StringProperty('label', label))
      ..add(
        FlagProperty('isSelected', value: isSelected, ifFalse: 'not selected'),
      )
      ..add(
        ObjectFlagProperty<VoidCallback>('onTap', onTap, ifNull: 'disabled'),
      );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selectedColor = colorScheme.primary;
    final unselectedColor = colorScheme.onSurface.withValues(alpha: 0.6);

    // InkWell provides hover feedback
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? selectedColor : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? selectedColor : unselectedColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
