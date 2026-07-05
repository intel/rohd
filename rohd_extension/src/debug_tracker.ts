/* ---------------------------------------------------------------------------
 * Copyright (C) 2026 Intel Corporation.
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * debug_tracker.ts
 * Debug Adapter Tracker for the ROHD VS Code extension.
 *
 * Registers with VS Code's debug infrastructure via
 * `registerDebugAdapterTrackerFactory` to automatically intercept Dart
 * debug sessions.  Extracts the VM Service URI from DAP messages and
 * obtains the DTD URI from the Dart extension API — no manual
 * configuration required.
 *
 * Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
 * --------------------------------------------------------------------------- */

import * as vscode from 'vscode';
import * as dtdBridge from './dtd_bridge';

const output = vscode.window.createOutputChannel('ROHD Debug Tracker');

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

/** Per-session tracking data. */
interface SessionInfo {
  vmServiceUri?: string;
  vmServiceForwardedUri?: string;
  dtdUri?: string;
  dtdForwardedUri?: string;
}

const sessions = new Map<string, SessionInfo>();

/** The DTD URI obtained from the Dart extension API. */
let dartExtDtdUri: string | undefined;
let dartExtDtdForwardedUri: string | undefined;

// ---------------------------------------------------------------------------
// URI helpers (shared logic with uri_forwarder.ts)
// ---------------------------------------------------------------------------

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
// Dart extension DTD API
// ---------------------------------------------------------------------------

interface DartExtensionApi {
  dtdUri?: string;
  onDtdUriChanged?: (
    listener: (uri: string | undefined) => void,
    thisArgs?: unknown,
    disposables?: vscode.Disposable[],
  ) => vscode.Disposable;
}

function watchDtdFromDartExtension(context: vscode.ExtensionContext): void {
  const dartExt = vscode.extensions.getExtension('dart-code.dart-code');
  if (!dartExt) {
    output.appendLine('[DTD] Dart extension not found — will rely on DAP events only.');
    return;
  }

  async function processDtd(rawUri: string): Promise<void> {
    const wsUri = normalizeWsUri(rawUri, false);
    dartExtDtdUri = wsUri;
    output.appendLine(`[DTD] From Dart extension API: ${wsUri}`);

    const forwarded = await resolveForwardedUri(wsUri);
    dartExtDtdForwardedUri = forwarded;
    if (forwarded) {
      output.appendLine(`[DTD] Forwarded: ${forwarded}`);
    }

    // Feed the original (non-forwarded) DTD URI to the bridge.
    // The bridge runs on the same host as the DTD daemon, so it uses
    // the local port.  The forwarded port is only for remote clients.
    dtdBridge.connectIfNeeded(wsUri).catch((err) => {
      output.appendLine(`[DTD] Bridge connect failed: ${err}`);
    });
  }

  function handleApi(api: DartExtensionApi): void {
    if (api.dtdUri) {
      processDtd(api.dtdUri).catch((err) => {
        output.appendLine(`[DTD] Error processing DTD URI: ${err}`);
      });
    }
    if (api.onDtdUriChanged) {
      const disposable = api.onDtdUriChanged((uri) => {
        if (uri) {
          processDtd(uri).catch((err) => {
            output.appendLine(`[DTD] Error on DTD URI change: ${err}`);
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
      (err) => output.appendLine(`[DTD] Dart extension activation failed: ${err}`),
    );
  }
}

// ---------------------------------------------------------------------------
// Banner output
// ---------------------------------------------------------------------------

const EXTENSION_VERSION = '0.3.0';

async function printSessionBanner(
  session: vscode.DebugSession,
  info: SessionInfo,
): Promise<void> {
  const lines: string[] = [];

  lines.push(`ROHD ${EXTENSION_VERSION}:  Extension loaded for FLC crossprobing.`);
  lines.push('');

  // DTD: prefer session-specific, fall back to Dart extension API
  const dtdOrig = info.dtdUri ?? dartExtDtdUri;
  const dtdFwd = info.dtdForwardedUri ?? dartExtDtdForwardedUri;
  if (dtdOrig) {
    lines.push('DTD:');
    lines.push(`  URI: ${dtdOrig}`);
    if (dtdFwd) {
      lines.push(`  Fwd: ${dtdFwd}`);
    }
  }

  if (info.vmServiceUri) {
    lines.push('VM:');
    lines.push(`  URI: ${info.vmServiceUri}`);
    if (info.vmServiceForwardedUri) {
      lines.push(`  Fwd: ${info.vmServiceForwardedUri}`);
    }
  }

  const banner = '═'.repeat(60);
  const block = [banner, ...lines, banner].join('\n');

  // Debug console
  vscode.debug.activeDebugConsole.appendLine('');
  vscode.debug.activeDebugConsole.appendLine(block);

  // Output channel (persists across sessions)
  output.appendLine('');
  output.appendLine(block);

  // Popup with DTD URI for quick copy
  const popupUri = dtdFwd ?? dtdOrig;
  if (popupUri) {
    const action = await vscode.window.showInformationMessage(
      `ROHD DTD: ${popupUri}`,
      'Copy',
    );
    if (action === 'Copy') {
      await vscode.env.clipboard.writeText(popupUri);
      vscode.window.showInformationMessage('DTD URI copied to clipboard.');
    }
  }
}

// ---------------------------------------------------------------------------
// Debug Adapter Tracker
// ---------------------------------------------------------------------------

class RohdDebugAdapterTracker implements vscode.DebugAdapterTracker {
  private readonly session: vscode.DebugSession;

  constructor(session: vscode.DebugSession) {
    this.session = session;
  }

  onWillStartSession(): void {
    output.appendLine(
      `[Tracker] Debug session starting: "${this.session.name}" (${this.session.id})`,
    );
    sessions.set(this.session.id, {});
  }

  onDidSendMessage(message: unknown): void {
    // The Dart debug adapter sends an "event" message with
    // event === "dart.debuggerUris" containing the VM Service URI.
    const msg = message as Record<string, unknown>;
    if (msg.type !== 'event') { return; }

    if (msg.event === 'dart.debuggerUris') {
      const body = msg.body as Record<string, unknown> | undefined;
      const vmUri = body?.vmServiceUri as string | undefined;
      if (vmUri) {
        this.processVmServiceUri(vmUri);
      }
    }
  }

  onWillStopSession(): void {
    output.appendLine(
      `[Tracker] Debug session ending: "${this.session.name}" (${this.session.id})`,
    );
    sessions.delete(this.session.id);
  }

  onError(error: Error): void {
    output.appendLine(`[Tracker] Error in session "${this.session.name}": ${error.message}`);
  }

  private async processVmServiceUri(rawUri: string): Promise<void> {
    const vmUri = normalizeWsUri(rawUri, true);
    const info = sessions.get(this.session.id) ?? {};
    info.vmServiceUri = vmUri;

    output.appendLine(`[Tracker] VM Service URI: ${vmUri}`);

    const forwarded = await resolveForwardedUri(vmUri);
    info.vmServiceForwardedUri = forwarded;
    if (forwarded) {
      output.appendLine(`[Tracker] VM Service Forwarded: ${forwarded}`);
    }

    // Copy DTD info from Dart extension API into session info
    if (dartExtDtdUri) {
      info.dtdUri = dartExtDtdUri;
      info.dtdForwardedUri = dartExtDtdForwardedUri;

      // Ensure the DTD bridge is connected now that we have a session.
      // Use the original (non-forwarded) URI — bridge is local.
      dtdBridge.connectIfNeeded(dartExtDtdUri).catch((err) => {
        output.appendLine(`[Tracker] Bridge connect failed: ${err}`);
      });
    }

    sessions.set(this.session.id, info);
    await printSessionBanner(this.session, info);
  }
}

class RohdDebugAdapterTrackerFactory implements vscode.DebugAdapterTrackerFactory {
  createDebugAdapterTracker(
    session: vscode.DebugSession,
  ): vscode.ProviderResult<vscode.DebugAdapterTracker> {
    return new RohdDebugAdapterTracker(session);
  }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/** Get session info for the active debug session. */
export function getActiveSessionInfo(): SessionInfo | undefined {
  const session = vscode.debug.activeDebugSession;
  if (!session) { return undefined; }
  return sessions.get(session.id);
}

/** Get the DTD URI (forwarded preferred, original fallback). */
export function getDtdUri(): string | undefined {
  const info = getActiveSessionInfo();
  return info?.dtdForwardedUri ?? info?.dtdUri ?? dartExtDtdForwardedUri ?? dartExtDtdUri;
}

/** Get the VM Service URI (forwarded preferred, original fallback). */
export function getVmServiceUri(): string | undefined {
  const info = getActiveSessionInfo();
  return info?.vmServiceForwardedUri ?? info?.vmServiceUri;
}

export function activate(context: vscode.ExtensionContext): void {
  output.appendLine('[Debug Tracker] Activating...');

  // Watch for DTD URI from the Dart extension API
  watchDtdFromDartExtension(context);

  // Register the tracker factory for Dart debug sessions
  context.subscriptions.push(
    vscode.debug.registerDebugAdapterTrackerFactory(
      'dart',
      new RohdDebugAdapterTrackerFactory(),
    ),
  );

  // Also register for generic debug types in case Dart sessions
  // use a different type identifier
  context.subscriptions.push(
    vscode.debug.registerDebugAdapterTrackerFactory(
      '*',
      {
        createDebugAdapterTracker(session: vscode.DebugSession) {
          // Only track Dart-related sessions
          if (session.type === 'dart' || session.type === 'flutter') {
            // Already tracked by the 'dart' factory above; skip duplication.
            return undefined;
          }
          return undefined;
        },
      },
    ),
  );

  // Command to show forwarded URIs for the active session
  context.subscriptions.push(
    vscode.commands.registerCommand('rohd.showForwardedUris', () => {
      const info = getActiveSessionInfo();
      if (!info) {
        vscode.window.showWarningMessage('No active Dart debug session.');
        return;
      }

      const lines: string[] = [];
      if (info.dtdUri) {
        lines.push(`DTD: ${info.dtdUri}`);
        if (info.dtdForwardedUri) { lines.push(`DTD Fwd: ${info.dtdForwardedUri}`); }
      } else if (dartExtDtdUri) {
        lines.push(`DTD: ${dartExtDtdUri}`);
        if (dartExtDtdForwardedUri) { lines.push(`DTD Fwd: ${dartExtDtdForwardedUri}`); }
      }
      if (info.vmServiceUri) {
        lines.push(`VM: ${info.vmServiceUri}`);
        if (info.vmServiceForwardedUri) { lines.push(`VM Fwd: ${info.vmServiceForwardedUri}`); }
      }

      if (lines.length === 0) {
        vscode.window.showWarningMessage('URIs not yet available. Start a debug session first.');
        return;
      }

      output.appendLine(lines.join('\n'));
      output.show(true);
    }),
  );

  output.appendLine('[Debug Tracker] Activated — tracking Dart debug sessions.');
}

export function deactivate(): void {
  sessions.clear();
  dartExtDtdUri = undefined;
  dartExtDtdForwardedUri = undefined;
}
