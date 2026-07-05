/* ---------------------------------------------------------------------------
 * Copyright (C) 2026 Intel Corporation.
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * uri_forwarder.ts
 * Resolves and displays DTD and VM Service URIs with port-forwarding
 * awareness.  When running inside a dev container or remote session,
 * VS Code's `asExternalUri` may map container-internal ports to
 * host-visible ports.  This module detects that and shows both the
 * original and forwarded URIs so they can be pasted into the ROHD
 * DevTools GUI.
 *
 * Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
 * --------------------------------------------------------------------------- */

import * as vscode from 'vscode';

const EXTENSION_VERSION = '0.2.0';

let outputChannel: vscode.OutputChannel;

/** Map of session id → last known VM Service URI (container-internal). */
const sessionVmUris = new Map<string, string>();

/** Latest original DTD URI (container-internal). */
let originalDtdUri: string | undefined;

/** Latest forwarded DTD URI, undefined if no forwarding occurred. */
let forwardedDtdUri: string | undefined;

// ---------------------------------------------------------------------------
// URI helpers
// ---------------------------------------------------------------------------

/**
 * Given a raw WS URI, resolve via `vscode.env.asExternalUri` to get the
 * port-forwarded equivalent.  Returns the forwarded URI string, or
 * `undefined` if no forwarding occurred (i.e. authority is unchanged).
 */
async function resolveForwardedUri(
  rawWsUri: string,
): Promise<string | undefined> {
  try {
    const httpUri = rawWsUri
      .replace(/^ws:\/\//, 'http://')
      .replace(/^wss:\/\//, 'https://');

    const parsed = vscode.Uri.parse(httpUri);
    const resolved = await vscode.env.asExternalUri(parsed);

    const scheme = resolved.scheme === 'https' ? 'wss' : 'ws';
    const forwarded = `${scheme}://${resolved.authority}${parsed.path}`;

    if (resolved.authority !== parsed.authority) {
      return forwarded;
    }
    return undefined;
  } catch {
    return undefined;
  }
}

/** Normalize a URI to ws:// scheme; optionally ensure a /ws suffix. */
function normalizeWsUri(uri: string, ensureWsSuffix: boolean): string {
  let u = uri;
  if (u.startsWith('http://')) {
    u = u.replace('http://', 'ws://');
  } else if (u.startsWith('https://')) {
    u = u.replace('https://', 'wss://');
  }
  if (ensureWsSuffix && !u.endsWith('/ws')) {
    u = u.replace(/\/?$/, '/ws');
  }
  return u;
}

// ---------------------------------------------------------------------------
// Dart extension API typings (subset)
// ---------------------------------------------------------------------------

interface DartExtensionApi {
  dtdUri?: string;
  onDtdUriChanged?: (
    listener: (uri: string | undefined) => void,
    thisArgs?: unknown,
    disposables?: vscode.Disposable[],
  ) => vscode.Disposable;
}

// ---------------------------------------------------------------------------
// DTD URI handling
// ---------------------------------------------------------------------------

async function processDtdUri(rawUri: string): Promise<void> {
  const wsUri = normalizeWsUri(rawUri, false);
  originalDtdUri = wsUri;
  outputChannel.appendLine(`[DTD] Original: ${wsUri}`);

  const forwarded = await resolveForwardedUri(wsUri);
  forwardedDtdUri = forwarded;
  if (forwarded) {
    outputChannel.appendLine(`[DTD] Forwarded: ${forwarded}`);
  }
}

function watchDtdUri(context: vscode.ExtensionContext): void {
  const dartExt = vscode.extensions.getExtension('dart-code.dart-code');
  if (!dartExt) {
    outputChannel.appendLine(
      '[DTD] Dart extension not found — DTD URI detection disabled.',
    );
    return;
  }

  function handleApi(api: DartExtensionApi): void {
    if (api.dtdUri) {
      processDtdUri(api.dtdUri).catch((err) => {
        outputChannel.appendLine(`[DTD] Error: ${err}`);
      });
    }
    if (api.onDtdUriChanged) {
      const disposable = api.onDtdUriChanged((uri) => {
        if (uri) {
          processDtdUri(uri).catch((err) => {
            outputChannel.appendLine(`[DTD] Error: ${err}`);
          });
        }
      });
      if (disposable) {
        context.subscriptions.push(disposable);
      }
    }
  }

  if (dartExt.isActive) {
    handleApi(dartExt.exports as DartExtensionApi);
  } else {
    dartExt.activate().then(
      (api) => handleApi(api as DartExtensionApi),
      (err) =>
        outputChannel.appendLine(
          `[DTD] Dart extension activation failed: ${err}`,
        ),
    );
  }
}

// ---------------------------------------------------------------------------
// Consolidated output
// ---------------------------------------------------------------------------

/**
 * Print a formatted block with the ROHD version, FLC info, and the
 * DTD / VM Service URIs (original + forwarded when port differs).
 */
async function printConsolidatedBlock(
  vmOriginal: string,
  vmForwarded: string | undefined,
  session: vscode.DebugSession,
): Promise<void> {
  const lines: string[] = [];

  lines.push(`ROHD ${EXTENSION_VERSION}:  Extension loaded for FLC crossprobing.`);
  lines.push('');

  if (originalDtdUri) {
    lines.push('DTD:');
    lines.push(`  URI: ${originalDtdUri}`);
    if (forwardedDtdUri) {
      lines.push(`  Fwd: ${forwardedDtdUri}`);
    }
  }

  lines.push('VM:');
  lines.push(`  URI: ${vmOriginal}`);
  if (vmForwarded) {
    lines.push(`  Fwd: ${vmForwarded}`);
  }

  const banner = '═'.repeat(60);
  const block = [banner, ...lines, banner].join('\n');

  // Debug console
  vscode.debug.activeDebugConsole.appendLine('');
  vscode.debug.activeDebugConsole.appendLine(block);

  // Output channel (persists across sessions)
  outputChannel.appendLine('');
  outputChannel.appendLine(block);

  // Show the most useful forwarded URI in a popup for quick copy
  const popupUri = forwardedDtdUri ?? originalDtdUri;
  if (popupUri) {
    const action = await vscode.window.showInformationMessage(
      `DTD: ${popupUri}`,
      'Copy',
    );
    if (action === 'Copy') {
      await vscode.env.clipboard.writeText(popupUri);
      vscode.window.showInformationMessage('DTD URI copied to clipboard.');
    }
  }
}

// ---------------------------------------------------------------------------
// VM Service URI handling
// ---------------------------------------------------------------------------

async function processVmServiceUri(
  rawUri: string,
  session: vscode.DebugSession,
): Promise<void> {
  const vmUri = normalizeWsUri(rawUri, true);
  sessionVmUris.set(session.id, vmUri);

  outputChannel.appendLine(`[VM] Original: ${vmUri}`);

  const forwarded = await resolveForwardedUri(vmUri);
  await printConsolidatedBlock(vmUri, forwarded, session);
}

// ---------------------------------------------------------------------------
// Public API — called from extension.ts
// ---------------------------------------------------------------------------

export function activate(context: vscode.ExtensionContext): void {
  outputChannel = vscode.window.createOutputChannel('ROHD URI Forwarder');

  // Start watching for the DTD URI early — it resolves before the
  // debug session starts so it will be ready when we print.
  watchDtdUri(context);

  // Listen for the DAP custom event "dart.debuggerUris"
  context.subscriptions.push(
    vscode.debug.onDidReceiveDebugSessionCustomEvent((e) => {
      if (e.event !== 'dart.debuggerUris') {
        return;
      }

      const uri = e.body?.vmServiceUri as string | undefined;
      if (!uri) {
        outputChannel.appendLine(
          '[URI Forwarder] dart.debuggerUris event received but no vmServiceUri in body.',
        );
        return;
      }

      outputChannel.appendLine(
        `[URI Forwarder] Received dart.debuggerUris for session "${e.session.name}".`,
      );

      processVmServiceUri(uri, e.session).catch((err) => {
        outputChannel.appendLine(`[URI Forwarder] Error: ${err}`);
      });
    }),
  );

  // Clean up stored URIs when sessions end
  context.subscriptions.push(
    vscode.debug.onDidTerminateDebugSession((session) => {
      sessionVmUris.delete(session.id);
    }),
  );

  // Manual command: re-resolve and re-print for the active session
  context.subscriptions.push(
    vscode.commands.registerCommand('rohd.showForwardedUris', async () => {
      const session = vscode.debug.activeDebugSession;
      if (!session) {
        vscode.window.showWarningMessage('No active debug session.');
        return;
      }

      const uri = sessionVmUris.get(session.id);
      if (!uri) {
        vscode.window.showWarningMessage(
          'VM Service URI not yet available for this session. ' +
            'It will be displayed automatically once the Dart VM starts.',
        );
        return;
      }

      await processVmServiceUri(uri, session);
    }),
  );

  outputChannel.appendLine('[URI Forwarder] Activated.');
}

export function deactivate(): void {
  sessionVmUris.clear();
  originalDtdUri = undefined;
  forwardedDtdUri = undefined;
  outputChannel?.dispose();
}
