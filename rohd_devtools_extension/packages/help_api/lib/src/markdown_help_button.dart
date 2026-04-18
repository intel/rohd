// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// markdown_help_button.dart
// A generic help button driven by a markdown asset file.
//
// The markdown file contains two sections separated by <!-- details -->:
//   - Above the marker: plain-text tooltip shown on hover
//   - Below the marker: markdown rendered in the click-open dialog
//
// The markdown file is also directly viewable in any markdown previewer
// (GitHub, VS Code, etc.) because both sections are valid markdown and
// the <!-- details --> separator is an invisible HTML comment.
//
// Details section format:
//   ## Heading           → section heading
//   | Key | Description | → key–description entry row (markdown table)
//   Paragraphs           → plain-text description
//
// 2026 March
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// A help button that loads its content from a markdown asset file.
///
/// The markdown file must contain a `<!-- tooltip -->` marker and a
/// `<!-- details -->` marker. Text between those markers becomes the
/// hover tooltip; text after `<!-- details -->` is rendered as the
/// click-open dialog body.
///
/// The first line of the file (an `# H1` heading) is used as the dialog
/// title. Everything before `<!-- tooltip -->` is ignored at runtime
/// (it serves as the visible title when previewing the raw markdown).
///
/// ### Markdown file layout
///
/// ```markdown
/// # 🌳 My Tool — Help          ← dialog title (H1)
///
/// <!-- tooltip -->
///
/// Short keybinding summary      ← hover tooltip (plain text)
/// shown on mouse hover.
///
/// <!-- details -->
///
/// ## Section                    ← dialog section heading
///
/// | Key | Description |         ← table header (required before rows)
/// |-----|-------------|
/// | F   | Fit to canvas |       ← key–description entry
///
/// Any paragraph text.           ← rendered as body text
/// ```
class MarkdownHelpButton extends StatefulWidget {
  /// Path to the markdown asset file (e.g. `assets/help/my_help.md`).
  final String assetPath;

  /// Whether the current theme is dark mode.
  final bool isDark;

  /// Optional override for the button label (defaults to `❓`).
  final String label;

  /// Optional widget to use as the button icon instead of [label].
  ///
  /// When non-null, this widget is displayed instead of `Text(label)`.
  /// Use this on platforms where the emoji [label] would not render
  /// (e.g. Linux without NotoColorEmoji), passing an `Icon(Icons.help_outline)`
  /// or similar Material icon.
  final Widget? labelIcon;

  /// Optional package name that owns the asset.
  ///
  /// When non-null the actual asset path becomes
  /// `packages/$package/$assetPath`, which is how Flutter resolves assets
  /// declared in dependency packages.
  final String? package;

  /// Optional widget shown before the dialog title text.
  ///
  /// Use this to display a custom icon (e.g. a `CustomPaint` widget)
  /// next to the dialog title instead of relying on emoji characters
  /// that may not render on all platforms.
  final Widget? titleIcon;

  /// Create a [MarkdownHelpButton].
  const MarkdownHelpButton({
    required this.assetPath,
    required this.isDark,
    this.label = '❓',
    this.labelIcon,
    this.package,
    this.titleIcon,
    super.key,
  });

  @override
  State<MarkdownHelpButton> createState() => _MarkdownHelpButtonState();
}

class _MarkdownHelpButtonState extends State<MarkdownHelpButton> {
  /// Parsed help content, loaded once from the asset.
  _HelpContent? _content;

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  @override
  void didUpdateWidget(MarkdownHelpButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetPath != widget.assetPath ||
        oldWidget.package != widget.package) {
      _loadContent();
    }
  }

  Future<void> _loadContent() async {
    try {
      String raw;
      if (widget.package != null) {
        // Try the package-qualified path first (works when embedded as a
        // dependency in a host app), then fall back to the bare asset path
        // (standalone mode). This order avoids a spurious 404 on the web
        // when the bare path doesn't exist.
        // Use catch-all because rootBundle.loadString throws FlutterError
        // (an Error, not Exception) when the asset is missing.
        try {
          raw = await rootBundle
              .loadString('packages/${widget.package}/${widget.assetPath}');
          // ignore: avoid_catches_without_on_clauses
        } catch (_) {
          raw = await rootBundle.loadString(widget.assetPath);
        }
      } else {
        raw = await rootBundle.loadString(widget.assetPath);
      }
      if (mounted) {
        setState(() {
          _content = _HelpContent.parse(raw);
        });
      }
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      debugPrint('Failed to load help asset: $e');
      if (mounted) {
        setState(() {
          _content = _HelpContent.parse(
            '# Help unavailable\n\n<!-- tooltip -->\n\n'
            'Help content could not be loaded.\n\n<!-- details -->\n\n'
            'Error: $e',
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final tooltip = _content?.tooltip ?? 'Loading help…';

    return Tooltip(
      message: tooltip,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? Colors.white24 : Colors.black12,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      textStyle: TextStyle(
        fontSize: 12,
        fontFamily: 'monospace',
        color: isDark ? Colors.white : Colors.black87,
        height: 1.4,
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            if (_content != null) {
              _showHelpDialog(context, _content!,
                  isDark: isDark, titleIcon: widget.titleIcon);
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: widget.labelIcon ??
                Text(widget.label,
                    style: const TextStyle(fontSize: 18, inherit: false)),
          ),
        ),
      ),
    );
  }

  /// Show the help dialog with parsed markdown content.
  static void _showHelpDialog(
    BuildContext context,
    _HelpContent content, {
    required bool isDark,
    Widget? titleIcon,
  }) {
    final bgColor = isDark ? const Color(0xFF252526) : Colors.white;
    final fgColor = isDark ? Colors.white : Colors.black87;
    final headingColor = isDark ? Colors.blue[200]! : Colors.blue[800]!;
    final keyColor = isDark ? Colors.amber[200]! : Colors.amber[900]!;
    final dividerColor = isDark ? Colors.white24 : Colors.black12;

    final widgets = <Widget>[];
    for (final block in content.detailBlocks) {
      if (block is _HeadingBlock) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Text(block.text,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: headingColor,
              )),
        ));
      } else if (block is _EntryBlock) {
        widgets.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 200,
                child: Text(block.key,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: keyColor,
                    )),
              ),
              Expanded(
                child: Text(block.description,
                    style: TextStyle(fontSize: 13, color: fgColor)),
              ),
            ],
          ),
        ));
      } else if (block is _ParagraphBlock) {
        widgets.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child:
              Text(block.text, style: TextStyle(fontSize: 13, color: fgColor)),
        ));
      }
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: bgColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 600),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title row
                Row(
                  children: [
                    if (titleIcon != null) ...[
                      titleIcon,
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Text(content.title,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: fgColor,
                          )),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: fgColor, size: 20),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                Divider(color: dividerColor),
                // Scrollable content
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: widgets,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Parsed help content model
// ---------------------------------------------------------------------------

/// Parsed representation of a help markdown file.
class _HelpContent {
  /// Dialog title (from the `# H1` heading).
  final String title;

  /// Plain-text tooltip (between `<!-- tooltip -->` and `<!-- details -->`).
  final String tooltip;

  /// Parsed detail blocks (headings, entries, paragraphs).
  final List<_DetailBlock> detailBlocks;

  _HelpContent({
    required this.title,
    required this.tooltip,
    required this.detailBlocks,
  });

  /// Parse a raw markdown string into [_HelpContent].
  factory _HelpContent.parse(String raw) {
    const tooltipMarker = '<!-- tooltip -->';
    const detailsMarker = '<!-- details -->';

    final tooltipIdx = raw.indexOf(tooltipMarker);
    final detailsIdx = raw.indexOf(detailsMarker);

    // Extract title from the first # heading.
    String title = 'Help';
    final titleMatch = RegExp(r'^#\s+(.+)$', multiLine: true).firstMatch(raw);
    if (titleMatch != null) {
      title = titleMatch.group(1)!.trim();
    }

    // Extract tooltip text.
    String tooltip = '';
    if (tooltipIdx >= 0 && detailsIdx > tooltipIdx) {
      tooltip =
          raw.substring(tooltipIdx + tooltipMarker.length, detailsIdx).trim();
    }

    // Parse detail blocks.
    final detailBlocks = <_DetailBlock>[];
    if (detailsIdx >= 0) {
      final detailsRaw = raw.substring(detailsIdx + detailsMarker.length);
      detailBlocks.addAll(_parseDetails(detailsRaw));
    }

    return _HelpContent(
      title: title,
      tooltip: tooltip,
      detailBlocks: detailBlocks,
    );
  }

  /// Parse the details section into blocks.
  static List<_DetailBlock> _parseDetails(String raw) {
    final blocks = <_DetailBlock>[];
    final lines = raw.split('\n');

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();

      // Skip empty lines
      if (trimmed.isEmpty) {
        continue;
      }

      // ## Heading
      if (trimmed.startsWith('## ')) {
        blocks.add(_HeadingBlock(trimmed.substring(3).trim()));
        continue;
      }

      // Table separator row (|---|---|) — skip
      if (RegExp(r'^\|[\s\-:|]+\|$').hasMatch(trimmed)) {
        continue;
      }

      // Table header row (| Key | Description |) — skip
      if (trimmed.startsWith('|') &&
          trimmed.endsWith('|') &&
          i + 1 < lines.length &&
          RegExp(r'^\|[\s\-:|]+\|$').hasMatch(lines[i + 1].trim())) {
        continue;
      }

      // Table data row (| key | description |)
      if (trimmed.startsWith('|') && trimmed.endsWith('|')) {
        final cells = trimmed
            .substring(1, trimmed.length - 1) // strip outer pipes
            .split('|')
            .map((c) => c.trim())
            .toList();
        if (cells.length >= 2) {
          blocks.add(_EntryBlock(
            key: _stripInlineCode(cells[0]),
            description: cells[1],
          ));
          continue;
        }
      }

      // Plain paragraph text (collect consecutive non-empty lines)
      final para = StringBuffer(trimmed);
      while (i + 1 < lines.length && lines[i + 1].trim().isNotEmpty) {
        final next = lines[i + 1].trim();
        // Stop at headings, table rows, or markers
        if (next.startsWith('## ') ||
            next.startsWith('|') ||
            next.startsWith('<!--')) {
          break;
        }
        i++;
        para.write(' ${lines[i].trim()}');
      }
      blocks.add(_ParagraphBlock(para.toString()));
    }

    return blocks;
  }

  /// Strip backtick inline code markers: `text` → text.
  static String _stripInlineCode(String s) => s.replaceAll('`', '');
}

// ---------------------------------------------------------------------------
// Detail block types
// ---------------------------------------------------------------------------

sealed class _DetailBlock {}

class _HeadingBlock extends _DetailBlock {
  final String text;
  _HeadingBlock(this.text);
}

class _EntryBlock extends _DetailBlock {
  final String key;
  final String description;
  _EntryBlock({required this.key, required this.description});
}

class _ParagraphBlock extends _DetailBlock {
  final String text;
  _ParagraphBlock(this.text);
}
