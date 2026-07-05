/* ---------------------------------------------------------------------------
 * Copyright (C) 2026 Intel Corporation.
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * extension.ts
 * Main entry point for the ROHD VS Code extension.
 *
 * Provides:
 * - ROHD Dart code snippets (carried forward from v0.0.5)
 * - Cross-probe source navigation commands for ROHD viewer extensions
 *
 * Original snippets by: Yao Jing Quek <yao.jing.quek@intel.com>
 * Cross-probe navigation by: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
 * --------------------------------------------------------------------------- */

import * as vscode from 'vscode';
import * as sourceNavigator from './source_navigator';
import * as dtdBridge from './dtd_bridge';
import * as debugTracker from './debug_tracker';
import * as conditionalCompletions from './conditional_completions';
import * as flcService from './flc_service';

export function activate(context: vscode.ExtensionContext): void {
  console.log('ROHD extension is now active (v0.3.0)');

  // Initialise the FLC service with the extension path so it can locate
  // the compiled flc_lookup binary.
  flcService.initialize(context.extensionPath);

  // Register cross-probe → editor navigation commands.
  // These are invoked by ROHD viewer extensions (schematic, wave) via
  // vscode.commands.executeCommand('rohd.openSourceLocation', ...).
  sourceNavigator.registerCommands(context);

  // ── FLC commands — viewer extensions delegate here ──────────────────────

  // rohd.queryModule: resolve available source formats for a module.
  // Args: { flcPath: string, module: string | null }
  // Returns: ModuleInfo (extensionAvailable, module, formats, ...)
  context.subscriptions.push(
    vscode.commands.registerCommand(
      'rohd.queryModule',
      (args: { flcPath: string; module: string | null }) =>
        flcService.queryModule(args.flcPath, args.module),
    ),
  );

  // rohd.lookupSignal: resolve source frames for a signal.
  // Args: { flcPath: string, module: string | null, signal: string, format?: string }
  // Returns: SourceFrame[]
  context.subscriptions.push(
    vscode.commands.registerCommand(
      'rohd.lookupSignal',
      (args: { flcPath: string; module: string | null; signal: string; format?: string }) =>
        flcService.lookupSignal(args.flcPath, args.module, args.signal, args.format),
    ),
  );

  // rohd.resolveFlcPath: find the .flc.json sidecar for a document path.
  // Args: { documentFsPath: string }
  // Returns: string | null
  context.subscriptions.push(
    vscode.commands.registerCommand(
      'rohd.resolveFlcPath',
      (args: { documentFsPath: string }) =>
        flcService.resolveFlcPath(args.documentFsPath),
    ),
  );

  // Activate the DTD bridge for receiving cross-probe requests from
  // the ROHD DevTools extension running in a remote iframe.
  dtdBridge.activate(context);

  // Register with the debug adapter to automatically intercept Dart
  // debug sessions, capture VM Service + DTD URIs, and print the
  // consolidated banner.  Replaces the old passive uri_forwarder.
  debugTracker.activate(context);

  // Register context-aware ROHD completions if the user has opted in.
  activateCompletionsIfEnabled(context);

  // Re-check when the setting changes at runtime.
  context.subscriptions.push(
    vscode.workspace.onDidChangeConfiguration(e => {
      if (e.affectsConfiguration('rohd.enableCompletions')) {
        activateCompletionsIfEnabled(context);
      }
    }),
  );
}

let completionsDisposable: vscode.Disposable | undefined;

async function activateCompletionsIfEnabled(
  context: vscode.ExtensionContext,
): Promise<void> {
  const config = vscode.workspace.getConfiguration('rohd');
  let enabled: boolean | undefined = config.get<boolean | null>('enableCompletions') ?? undefined;

  if (enabled === undefined) {
    // First time — ask the user.
    const choice = await vscode.window.showInformationMessage(
      'Enable ROHD context-aware code completions?',
      'Yes', 'No',
    );
    if (choice === 'Yes') {
      enabled = true;
    } else if (choice === 'No') {
      enabled = false;
    } else {
      return; // Dismissed — ask again next time.
    }
    await config.update('enableCompletions', enabled, vscode.ConfigurationTarget.Global);
  }

  if (enabled && !completionsDisposable) {
    completionsDisposable = conditionalCompletions.activate(context);
    context.subscriptions.push(completionsDisposable);
  } else if (!enabled && completionsDisposable) {
    completionsDisposable.dispose();
    completionsDisposable = undefined;
  }
}

export function deactivate(): void {
  debugTracker.deactivate();
  dtdBridge.dispose();
  sourceNavigator.dispose();
}
