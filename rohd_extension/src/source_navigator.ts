/* ---------------------------------------------------------------------------
 * Copyright (C) 2026 Intel Corporation.
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * source_navigator.ts
 * Cross-probe → VS Code editor navigation module.
 *
 * Receives source location requests from ROHD viewer extensions (schematic,
 * wave) and navigates the VS Code editor to the corresponding file/line/col.
 * Supports multi-frame stack traces with cycling.
 *
 * Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
 * --------------------------------------------------------------------------- */

import * as vscode from 'vscode';

const output = vscode.window.createOutputChannel('ROHD Source Navigator');

/** A single source location frame. */
export interface SourceFrame {
  /** File path (package-relative, e.g. `lib/src/foo.dart`). */
  file: string;
  /** 1-based line number. */
  line: number;
  /** 1-based column number. */
  col: number;
  /** Optional description (e.g. function name from stack trace). */
  desc?: string;
  /** Frame type: 'sv' for SystemVerilog, 'rohd' for ROHD Dart source. */
  type?: string;
}

// ---------------------------------------------------------------------------
// Frame cycling state
// ---------------------------------------------------------------------------

let currentFrames: SourceFrame[] = [];
let currentFrameIndex = 0;
let statusBarItem: vscode.StatusBarItem | undefined;
let statusBarTimeout: ReturnType<typeof setTimeout> | undefined;

// Highlight decoration for the target symbol (yellow flash).
const highlightDecoration = vscode.window.createTextEditorDecorationType({
  backgroundColor: 'rgba(255, 213, 79, 0.35)',
});
let highlightTimeout: ReturnType<typeof setTimeout> | undefined;

// ---------------------------------------------------------------------------
// Public API — called via vscode.commands.executeCommand()
// ---------------------------------------------------------------------------

/**
 * Navigate to a single source location.
 *
 * @param args `{ file: string, line: number, col: number }`
 */
export async function openSourceLocation(
  args: { file: string; line: number; col: number },
): Promise<void> {
  if (!args || !args.file) {
    vscode.window.showWarningMessage('ROHD: No source location provided.');
    return;
  }
  // Clear any previous frame cycling state.
  currentFrames = [{ file: args.file, line: args.line, col: args.col }];
  currentFrameIndex = 0;
  hideStatusBar();
  await navigateToFrame(currentFrames[0]);
}

/**
 * Navigate to the first of multiple source location frames and enable
 * cycling through them.
 *
 * @param args `{ frames: SourceFrame[], index?: number }`
 */
export async function openSourceLocations(
  args: { frames: SourceFrame[]; index?: number },
): Promise<void> {
  if (!args || !args.frames || args.frames.length === 0) {
    vscode.window.showWarningMessage('ROHD: No source locations provided.');
    return;
  }
  currentFrames = args.frames;
  currentFrameIndex = args.index ?? 0;
  if (currentFrameIndex < 0 || currentFrameIndex >= currentFrames.length) {
    currentFrameIndex = 0;
  }
  updateStatusBar();

  // Navigate to the primary frame.
  await navigateToFrame(currentFrames[currentFrameIndex]);

  // Also open the first frame of each other type (e.g. SV alongside ROHD)
  // so both files are visible simultaneously.
  const openedTypes = new Set([currentFrames[currentFrameIndex].type || 'rohd']);
  for (const frame of currentFrames) {
    const t = frame.type || 'rohd';
    if (!openedTypes.has(t)) {
      openedTypes.add(t);
      await navigateToFrame(frame, true);
    }
  }
}

/** Advance to the next frame in the current frame list. */
export async function nextSourceLocation(): Promise<void> {
  if (currentFrames.length === 0) { return; }
  currentFrameIndex = (currentFrameIndex + 1) % currentFrames.length;
  updateStatusBar();
  await navigateToFrame(currentFrames[currentFrameIndex]);
}

/** Go back to the previous frame in the current frame list. */
export async function prevSourceLocation(): Promise<void> {
  if (currentFrames.length === 0) { return; }
  currentFrameIndex =
    (currentFrameIndex - 1 + currentFrames.length) % currentFrames.length;
  updateStatusBar();
  await navigateToFrame(currentFrames[currentFrameIndex]);
}

// ---------------------------------------------------------------------------
// Navigation implementation
// ---------------------------------------------------------------------------

/**
 * Open (or reuse) an editor tab for the given frame and scroll to the
 * target line.  Tries multiple candidate paths until one succeeds.
 */
async function navigateToFrame(frame: SourceFrame, preserveFocus = false): Promise<void> {
  const candidates = resolveCandidates(frame.file);
  if (candidates.length === 0) {
    vscode.window.showWarningMessage(
      `ROHD: Could not resolve file: ${frame.file}`,
    );
    return;
  }

  // 0-based position from 1-based FLC data.
  const line = Math.max(0, frame.line - 1);
  const col = Math.max(0, frame.col - 1);
  const pos = new vscode.Position(line, col);
  const range = new vscode.Range(pos, pos);

  for (const uri of candidates) {
    try {
      const doc = await vscode.workspace.openTextDocument(uri);
      const docUriStr = doc.uri.toString();

      // Reuse an existing editor tab for this document if one is already
      // open, instead of always opening a new split.  Compare against
      // the document's canonical URI (not the candidate URI which may
      // contain unresolved `..` segments).
      let viewColumn = vscode.ViewColumn.Beside;
      for (const tab of vscode.window.tabGroups.all.flatMap(g => g.tabs)) {
        const tabInput = tab.input;
        if (tabInput instanceof vscode.TabInputText &&
            tabInput.uri.toString() === docUriStr) {
          viewColumn = tab.group.viewColumn;
          break;
        }
      }

      const editor = await vscode.window.showTextDocument(doc, {
        viewColumn,
        preserveFocus,
        selection: range,
      });

      editor.revealRange(
        new vscode.Range(pos, pos),
        vscode.TextEditorRevealType.InCenterIfOutsideViewport,
      );

      // Flash-highlight the symbol at the target position.
      flashHighlight(editor, line, col);

      output.appendLine(
        `Navigated to ${frame.file}:${frame.line}:${frame.col} (resolved: ${uri.fsPath})`,
      );
      return; // Success — stop trying candidates.
    } catch {
      // This candidate didn't work; try the next one.
      continue;
    }
  }

  // All candidates failed.
  vscode.window.showWarningMessage(
    `ROHD: Could not find file: ${frame.file}`,
  );
  output.appendLine(
    `Failed to resolve ${frame.file} (tried ${candidates.length} candidates)`,
  );
}

/**
 * Normalize a file path by collapsing `.` and `..` segments.
 *
 * FLC paths from SourceTraceRegistry often contain `.dart_tool/../lib/...`
 * which needs collapsing before resolution.
 */
function normalizePath(filePath: string): string {
  const isAbsolute = filePath.startsWith('/');
  const parts = filePath.split('/');
  const resolved: string[] = [];
  for (const part of parts) {
    if (part === '.' || part === '') {
      continue;
    } else if (part === '..' && resolved.length > 0 && resolved[resolved.length - 1] !== '..') {
      resolved.pop();
    } else {
      resolved.push(part);
    }
  }
  const joined = resolved.join('/');
  return isAbsolute ? '/' + joined : joined;
}

/**
 * Generate candidate URIs for a package-relative file path.
 *
 * Tries (in order):
 * 1. Normalized path relative to each workspace folder
 * 2. Normalized path relative to parent directories of each workspace
 *    folder (up to 4 levels — covers typical layouts where the ROHD
 *    package root is above the extension subdirectory)
 * 3. As an absolute path
 */
function resolveCandidates(filePath: string): vscode.Uri[] {
  const normalized = normalizePath(filePath);
  const candidates: vscode.Uri[] = [];
  const folders = vscode.workspace.workspaceFolders;

  if (folders) {
    for (const folder of folders) {
      // Direct: workspace root + normalized path
      candidates.push(vscode.Uri.joinPath(folder.uri, normalized));

      // SV files are often generated into a build/ directory.
      candidates.push(vscode.Uri.joinPath(folder.uri, 'build', normalized));

      // Walk up parent directories (the ROHD package root may be above
      // the workspace folder, e.g. merged/ vs merged/rohd_devtools_extension/rohd-schematic-viewer/)
      let parent = folder.uri;
      for (let i = 0; i < 4; i++) {
        parent = vscode.Uri.joinPath(parent, '..');
        candidates.push(vscode.Uri.joinPath(parent, normalized));
        candidates.push(vscode.Uri.joinPath(parent, 'build', normalized));
      }
    }
  }

  // Absolute path fallback.
  if (normalized.startsWith('/')) {
    candidates.push(vscode.Uri.file(normalized));
  }

  // Also try the original (un-normalized) path in case it's already correct.
  if (normalized !== filePath && folders) {
    for (const folder of folders) {
      candidates.push(vscode.Uri.joinPath(folder.uri, filePath));
    }
  }

  return candidates;
}

// ---------------------------------------------------------------------------
// Status bar
// ---------------------------------------------------------------------------

function updateStatusBar(): void {
  if (currentFrames.length <= 1) {
    hideStatusBar();
    return;
  }
  if (!statusBarItem) {
    statusBarItem = vscode.window.createStatusBarItem(
      vscode.StatusBarAlignment.Right,
      100,
    );
    statusBarItem.command = 'rohd.nextSourceLocation';
    statusBarItem.tooltip = 'Click to cycle through source frames';
  }
  const frame = currentFrames[currentFrameIndex];
  const shortFile = frame.file.split('/').pop() ?? frame.file;
  const typeTag = frame.type === 'sv' ? 'SV' : frame.type === 'rohd' ? 'ROHD' : 'Source';
  const desc = frame.desc ? ` ${frame.desc}` : '';
  statusBarItem.text = `$(source-control) ${typeTag} ${currentFrameIndex + 1}/${currentFrames.length}: ${shortFile}:${frame.line}${desc}`;
  statusBarItem.show();

  // Auto-hide after 15 seconds.
  if (statusBarTimeout) { clearTimeout(statusBarTimeout); }
  statusBarTimeout = setTimeout(() => hideStatusBar(), 15000);
}

function hideStatusBar(): void {
  statusBarItem?.hide();
  if (statusBarTimeout) {
    clearTimeout(statusBarTimeout);
    statusBarTimeout = undefined;
  }
}

// ---------------------------------------------------------------------------
// Highlight flash
// ---------------------------------------------------------------------------

function flashHighlight(editor: vscode.TextEditor, line: number, col: number): void {
  if (highlightTimeout) { clearTimeout(highlightTimeout); }

  const doc = editor.document;
  const pos = new vscode.Position(line, col);

  // Try to get the word range at the column position (symbol highlight).
  const wordRange = doc.getWordRangeAtPosition(pos);

  // Use the word range if found, otherwise highlight from column to end of line.
  const highlightRange = wordRange
    ?? new vscode.Range(pos, doc.lineAt(line).range.end);

  editor.setDecorations(highlightDecoration, [highlightRange]);

  // Remove highlight after 60 seconds.
  highlightTimeout = setTimeout(() => {
    editor.setDecorations(highlightDecoration, []);
  }, 60000);
}

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

/** Register all commands. Call from extension activate(). */
export function registerCommands(context: vscode.ExtensionContext): void {
  context.subscriptions.push(
    vscode.commands.registerCommand('rohd.openSourceLocation', openSourceLocation),
    vscode.commands.registerCommand('rohd.openSourceLocations', openSourceLocations),
    vscode.commands.registerCommand('rohd.nextSourceLocation', nextSourceLocation),
    vscode.commands.registerCommand('rohd.prevSourceLocation', prevSourceLocation),
  );
  output.appendLine('ROHD Source Navigator commands registered.');
}

/** Clean up. Call from extension deactivate(). */
export function dispose(): void {
  hideStatusBar();
  statusBarItem?.dispose();
  highlightDecoration.dispose();
}

// ---------------------------------------------------------------------------
// Frame enrichment — resolve enclosing method names via Document Symbols
// ---------------------------------------------------------------------------

/** A frame enriched with its enclosing method/class names. */
export interface EnrichedFrame extends SourceFrame {
  /** Enclosing method/function name (e.g. `"build"`). */
  methodName?: string;
  /** Enclosing class name (e.g. `"Serializer"`). */
  className?: string;
  /** Human-readable label: `"Serializer.build() — serializer.dart:55"`. */
  label?: string;
}

/**
 * Resolve the enclosing method name for a source location using the
 * VS Code Document Symbol Provider (backed by the Dart language server).
 */
async function resolveEnclosingSymbol(
  uri: vscode.Uri,
  line: number,
  col: number,
): Promise<{ methodName?: string; className?: string }> {
  try {
    const symbols = await vscode.commands.executeCommand<vscode.DocumentSymbol[]>(
      'vscode.executeDocumentSymbolProvider',
      uri,
    );
    if (!symbols || symbols.length === 0) {
      return {};
    }

    const pos = new vscode.Position(Math.max(0, line - 1), Math.max(0, col - 1));
    let methodName: string | undefined;
    let className: string | undefined;

    // Walk the symbol tree depth-first, tracking the innermost containing
    // function/method and its parent class.
    function walk(syms: vscode.DocumentSymbol[], parentClass?: string): void {
      for (const sym of syms) {
        if (!sym.range.contains(pos)) { continue; }

        if (sym.kind === vscode.SymbolKind.Class ||
            sym.kind === vscode.SymbolKind.Enum) {
          className = sym.name;
          walk(sym.children, sym.name);
        } else if (
          sym.kind === vscode.SymbolKind.Method ||
          sym.kind === vscode.SymbolKind.Function ||
          sym.kind === vscode.SymbolKind.Constructor
        ) {
          methodName = sym.name;
          if (parentClass) { className = parentClass; }
          // Continue into children in case there's a nested function.
          walk(sym.children, parentClass);
        } else {
          walk(sym.children, parentClass);
        }
      }
    }

    walk(symbols);
    return { methodName, className };
  } catch {
    return {};
  }
}

/**
 * Enrich a list of frames with enclosing method/class names.
 *
 * Opens each document (lazily — no visible editor tab) to query the
 * Document Symbol Provider.  Returns an enriched copy of each frame.
 */
export async function resolveFrames(
  frames: SourceFrame[],
): Promise<EnrichedFrame[]> {
  const enriched: EnrichedFrame[] = [];

  for (const frame of frames) {
    const candidates = resolveCandidates(frame.file);
    let methodName: string | undefined;
    let className: string | undefined;
    let resolved = false;

    for (const uri of candidates) {
      try {
        // Open the document without showing it — this triggers the
        // language server to analyse it if not already cached.
        await vscode.workspace.openTextDocument(uri);
        const result = await resolveEnclosingSymbol(uri, frame.line, frame.col);
        methodName = result.methodName;
        className = result.className;
        resolved = true;
        break;
      } catch {
        continue;
      }
    }

    // Build human-readable label.
    const shortFile = frame.file.split('/').pop() ?? frame.file;
    let label: string;
    if (className && methodName) {
      label = `${className}.${methodName}() — ${shortFile}:${frame.line}`;
    } else if (methodName) {
      label = `${methodName}() — ${shortFile}:${frame.line}`;
    } else if (className) {
      label = `${className} — ${shortFile}:${frame.line}`;
    } else {
      label = `${shortFile}:${frame.line}`;
    }

    enriched.push({
      ...frame,
      methodName,
      className,
      label,
    });

    if (!resolved) {
      output.appendLine(
        `[resolveFrames] Could not resolve symbols for ${frame.file}:${frame.line}`,
      );
    }
  }

  return enriched;
}
