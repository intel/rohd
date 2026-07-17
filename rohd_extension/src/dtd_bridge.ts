/* ---------------------------------------------------------------------------
 * Copyright (C) 2026 Intel Corporation.
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * dtd_bridge.ts
 * DTD (Dart Tooling Daemon) bridge for receiving cross-probe source
 * navigation requests from the ROHD DevTools extension.
 *
 * Registers a `rohd.goToSource` service method on the DTD so that the
 * DevTools extension can send resolved SourceFrame lists for navigation.
 *
 * Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
 * --------------------------------------------------------------------------- */

import * as vscode from 'vscode';
import { openSourceLocations, resolveFrames } from './source_navigator';
import * as flcService from './flc_service';

const output = vscode.window.createOutputChannel('ROHD DTD Bridge');

// ---------------------------------------------------------------------------
// Minimal JSON-RPC 2.0 server over WebSocket
// ---------------------------------------------------------------------------

let ws: import('ws').WebSocket | undefined;
let nextId = 1;
const pendingRequests = new Map<number, {
  resolve: (result: unknown) => void;
  reject: (error: Error) => void;
}>();

type RpcHandler = (params: Record<string, unknown>) => Promise<unknown>;
const methods = new Map<string, RpcHandler>();

const rohdDtdBridgeCapabilities = {
  rohdDtdBridge: 1,
  owner: 'rohd-vscode-extension',
};

function dtdResult(result: Record<string, unknown>): Record<string, unknown> {
  return { type: 'Success', ...result };
}

function sendJsonRpc(data: Record<string, unknown>): void {
  if (ws?.readyState === 1 /* OPEN */) {
    ws.send(JSON.stringify(data));
  }
}

function handleMessage(raw: string): void {
  let msg: Record<string, unknown>;
  try {
    msg = JSON.parse(raw);
  } catch {
    return;
  }

  // Response to a request we sent.
  if ('id' in msg && ('result' in msg || 'error' in msg)) {
    const id = msg.id as number;
    const pending = pendingRequests.get(id);
    if (pending) {
      pendingRequests.delete(id);
      if ('error' in msg) {
        pending.reject(new Error(JSON.stringify(msg.error)));
      } else {
        pending.resolve(msg.result);
      }
    }
    return;
  }

  // Incoming request or notification.
  if ('method' in msg) {
    const method = msg.method as string;
    const params = (msg.params ?? {}) as Record<string, unknown>;
    const handler = methods.get(method);

    if (handler && 'id' in msg) {
      // Request — send response.
      handler(params)
        .then(result => sendJsonRpc({ jsonrpc: '2.0', id: msg.id, result }))
        .catch(err =>
          sendJsonRpc({
            jsonrpc: '2.0',
            id: msg.id,
            error: { code: -32000, message: String(err) },
          }),
        );
    } else if (handler) {
      // Notification — fire and forget.
      handler(params).catch(() => {});
    }
  }
}

/** Send a JSON-RPC request and wait for the response. */
async function rpcRequest(
  method: string,
  params?: Record<string, unknown>,
): Promise<unknown> {
  return new Promise((resolve, reject) => {
    const id = nextId++;
    pendingRequests.set(id, { resolve, reject });
    sendJsonRpc({ jsonrpc: '2.0', id, method, params: params ?? {} });

    // Timeout after 10 seconds.
    setTimeout(() => {
      if (pendingRequests.has(id)) {
        pendingRequests.delete(id);
        reject(new Error(`RPC timeout: ${method}`));
      }
    }, 10000);
  });
}

// ---------------------------------------------------------------------------
// Service registration
// ---------------------------------------------------------------------------

/**
 * Register the `rohd.goToSource` handler.
 *
 * When the DevTools extension calls this service via DTD, the handler
 * parses the SourceFrame list and delegates to the existing
 * `openSourceLocations` command.
 */
function registerGoToSourceHandler(): void {
  methods.set('rohd.goToSource', async (params) => {
    const framesRaw = params.frames;
    if (!Array.isArray(framesRaw) || framesRaw.length === 0) {
      return dtdResult({ status: 'error', message: 'No frames provided' });
    }

    const index = typeof params.index === 'number' ? params.index : 0;

    output.appendLine(
      `[DTD] goToSource: ${framesRaw.length} frame(s), index=${index}`,
    );

    // Delegate to the existing source navigator.
    await openSourceLocations({ frames: framesRaw, index });
    return dtdResult({ status: 'ok', navigated: framesRaw.length });
  });

  methods.set('rohd.resolveFrames', async (params) => {
    const framesRaw = params.frames;
    if (!Array.isArray(framesRaw) || framesRaw.length === 0) {
      return dtdResult({ status: 'error', message: 'No frames provided' });
    }

    output.appendLine(
      `[DTD] resolveFrames: ${framesRaw.length} frame(s)`,
    );

    const enriched = await resolveFrames(framesRaw);
    return dtdResult({ status: 'ok', frames: enriched });
  });

  // Query which source formats are available for a module.
  // params: { flcPath: string, module: string | null }
  methods.set('rohd.queryModule', async (params) => {
    const flcPath = params.flcPath as string | undefined;
    const moduleName = (params.module as string | null) ?? null;

    if (!flcPath) {
      return dtdResult({ status: 'error', message: 'flcPath is required' });
    }

    output.appendLine(`[DTD] queryModule: module=${moduleName ?? '(any)'}, flcPath=${flcPath}`);
    const info = flcService.queryModule(flcPath, moduleName);
    return dtdResult({ status: 'ok', ...info });
  });

  // Look up signal source frames from a persisted .flc.json file.
  // params: { flcPath: string, module: string | null, signal: string, format?: string }
  methods.set('rohd.lookupSignal', async (params) => {
    const flcPath = params.flcPath as string | undefined;
    const moduleName = (params.module as string | null) ?? null;
    const signalName = params.signal as string | undefined;
    const format = params.format as string | undefined;

    if (!flcPath || !signalName) {
      return dtdResult({ status: 'error', message: 'flcPath and signal are required' });
    }

    output.appendLine(
      `[DTD] lookupSignal: signal=${signalName}, module=${moduleName ?? '(any)'}, format=${format ?? 'all'}`,
    );
    const frames = flcService.lookupSignal(flcPath, moduleName, signalName, format);
    return dtdResult({ status: 'ok', frames });
  });
}

// ---------------------------------------------------------------------------
// DTD connection lifecycle
// ---------------------------------------------------------------------------

let reconnectTimer: ReturnType<typeof setTimeout> | undefined;
let reconnectAttempts = 0;
let dtdUri: string | undefined;

// In-flight connection guard. `connectToDtd` is async (it awaits the dynamic
// `ws` import before assigning `ws`), so two near-simultaneous callers — e.g.
// activation-time discovery and the debug tracker — can both pass the
// `isConnected()` check (which is only OPEN, never CONNECTING) and open a
// second socket to the same URI. The second socket then fails registration
// with "Service already registered by another client." This flag is set
// synchronously at the top of `connectToDtd` to close that window.
let connecting = false;
let connectingUri: string | undefined;

/**
 * Connect to the DTD and register services.
 *
 * @param uri WebSocket URI of the Dart Tooling Daemon.
 */
async function connectToDtd(uri: string): Promise<boolean> {
  // Synchronous dedupe: ignore a second connect to a URI we are already
  // connecting to or connected to.
  if (connecting && connectingUri === uri) {
    output.appendLine(`[DTD] Connect already in progress for ${uri}; skipping`);
    return false;
  }
  if (isConnected() && dtdUri === uri) {
    return true;
  }

  connecting = true;
  connectingUri = uri;
  dtdUri = uri;

  try {
    // Dynamic import — ws is a Node.js dependency.
    const WebSocket = (await import('ws')).default;

    ws = new WebSocket(uri);

    return new Promise<boolean>((resolve) => {
      ws!.on('open', () => {
        output.appendLine(`[DTD] Connected to ${uri}`);
        reconnectAttempts = 0;
        connecting = false;
        connectingUri = undefined;

        registerGoToSourceHandler();

        // Register ourselves as a service on the DTD.
        rpcRequest('registerService', {
          service: 'rohd',
          method: 'goToSource',
          capabilities: rohdDtdBridgeCapabilities,
        }).then(() => {
          output.appendLine('[DTD] Registered rohd.goToSource service');
        }).catch((err) => {
          output.appendLine(`[DTD] Service registration note: ${err}`);
        });

        rpcRequest('registerService', {
          service: 'rohd',
          method: 'resolveFrames',
          capabilities: rohdDtdBridgeCapabilities,
        }).then(() => {
          output.appendLine('[DTD] Registered rohd.resolveFrames service');
        }).catch((err) => {
          output.appendLine(`[DTD] resolveFrames registration note: ${err}`);
        });

        rpcRequest('registerService', {
          service: 'rohd',
          method: 'queryModule',
          capabilities: rohdDtdBridgeCapabilities,
        }).then(() => {
          output.appendLine('[DTD] Registered rohd.queryModule service');
        }).catch((err) => {
          output.appendLine(`[DTD] queryModule registration note: ${err}`);
        });

        rpcRequest('registerService', {
          service: 'rohd',
          method: 'lookupSignal',
          capabilities: rohdDtdBridgeCapabilities,
        }).then(() => {
          output.appendLine('[DTD] Registered rohd.lookupSignal service');
        }).catch((err) => {
          output.appendLine(`[DTD] lookupSignal registration note: ${err}`);
        });

        resolve(true);
      });

      ws!.on('message', (data: Buffer | string) => {
        handleMessage(data.toString());
      });

      ws!.on('close', () => {
        output.appendLine('[DTD] Connection closed');
        ws = undefined;
        scheduleReconnect();
      });

      ws!.on('error', (err: Error) => {
        output.appendLine(`[DTD] Connection error: ${err.message}`);
        ws = undefined;
        connecting = false;
        connectingUri = undefined;
        resolve(false);
      });
    });
  } catch (err) {
    output.appendLine(`[DTD] Failed to connect: ${err}`);
    connecting = false;
    connectingUri = undefined;
    return false;
  }
}

function scheduleReconnect(): void {
  if (!dtdUri || reconnectTimer) return;

  // Exponential backoff: 2s, 4s, 8s, 16s, 32s max.
  const delay = Math.min(2000 * 2 ** reconnectAttempts, 32000);
  reconnectAttempts++;

  output.appendLine(`[DTD] Reconnecting in ${delay / 1000}s...`);
  reconnectTimer = setTimeout(async () => {
    reconnectTimer = undefined;
    if (dtdUri) {
      await connectToDtd(dtdUri);
    }
  }, delay);
}

// ---------------------------------------------------------------------------
// DTD URI discovery
// ---------------------------------------------------------------------------

/**
 * Try to discover the DTD URI from known sources.
 *
 * Order of precedence:
 * 1. `DART_TOOLING_DAEMON_URI` environment variable
 * 2. VS Code setting `rohd.dtdUri` (for manual override)
 *
 * Note: The Dart extension API DTD URI is discovered asynchronously by
 * debug_tracker.ts and fed to connectIfNeeded() when available.
 */
function discoverDtdUri(): string | undefined {
  // Environment variable (set by IDE or debug launcher).
  const envUri = process.env.DART_TOOLING_DAEMON_URI;
  if (envUri) {
    output.appendLine(`[DTD] URI from env: ${envUri}`);
    return envUri;
  }

  // VS Code setting.
  const config = vscode.workspace.getConfiguration('rohd');
  const configUri = config.get<string>('dtdUri');
  if (configUri) {
    output.appendLine(`[DTD] URI from setting: ${configUri}`);
    return configUri;
  }

  output.appendLine('[DTD] No DTD URI discovered (debug_tracker will push later)');
  return undefined;
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/** Whether the DTD bridge is connected. */
export function isConnected(): boolean {
  return ws?.readyState === 1;
}

/**
 * Connect to the DTD if not already connected.
 * Called by debug_tracker when the DTD URI is discovered from the Dart
 * extension API (which resolves after activation).
 */
export async function connectIfNeeded(uri: string): Promise<void> {
  if (isConnected()) {
    return; // Already connected — nothing to do.
  }
  if (connecting && connectingUri === uri) {
    return; // A connection to this URI is already in flight.
  }
  output.appendLine(`[DTD] Connecting via debug tracker: ${uri}`);
  await connectToDtd(uri);
}

/**
 * Activate the DTD bridge.
 *
 * Discovers the DTD URI and connects. If the URI is not available
 * at activation time, the bridge remains dormant and can be connected
 * later via the `rohd.connectDtd` command.
 */
export async function activate(context: vscode.ExtensionContext): Promise<void> {
  // Register a command for manual DTD connection.
  context.subscriptions.push(
    vscode.commands.registerCommand('rohd.connectDtd', async () => {
      const uri = await vscode.window.showInputBox({
        prompt: 'Enter the Dart Tooling Daemon WebSocket URI',
        placeHolder: 'ws://127.0.0.1:...',
        value: dtdUri ?? '',
      });
      if (uri) {
        await connectToDtd(uri);
      }
    }),
  );

  // Try automatic discovery.
  const uri = discoverDtdUri();
  if (uri) {
    await connectToDtd(uri);
  }
}

/** Clean up the DTD bridge. */
export async function dispose(): Promise<void> {
  if (reconnectTimer) {
    clearTimeout(reconnectTimer);
    reconnectTimer = undefined;
  }
  dtdUri = undefined;
  connecting = false;
  connectingUri = undefined;

  if (ws) {
    ws.close();
    ws = undefined;
  }

  pendingRequests.clear();
  methods.clear();
}
