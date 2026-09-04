import 'package:devtools_extensions/devtools_extensions.dart';

/// Sets whether the embedding DevTools extension uses a dark theme.
void setExtensionDarkThemeEnabled({required bool enabled}) {
  extensionManager.darkThemeEnabled.value = enabled;
}
