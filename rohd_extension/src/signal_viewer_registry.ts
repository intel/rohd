import * as vscode from 'vscode';

const output = vscode.window.createOutputChannel('ROHD Signal Viewers');

interface RegisterSignalViewerArgs {
  viewerId: string;
  label?: string;
  receiveCommand?: string;
  availabilityCommand?: string;
}

interface UnregisterSignalViewerArgs {
  viewerId: string;
}

interface GetSignalViewersArgs {
  excludeViewerId?: string;
}

interface SendSignalsArgs {
  sourceViewerId: string;
  signalPaths: string[];
}

interface SignalViewerRegistration {
  viewerId: string;
  label?: string;
  receiveCommand?: string;
  availabilityCommand?: string;
}

interface SignalViewerInfo {
  viewerId: string;
  label?: string;
  canReceiveSignals: boolean;
}

const viewers = new Map<string, SignalViewerRegistration>();

function viewerInfo(viewer: SignalViewerRegistration): SignalViewerInfo {
  const info: SignalViewerInfo = {
    viewerId: viewer.viewerId,
    canReceiveSignals: viewer.receiveCommand !== undefined,
  };
  if (viewer.label !== undefined) {
    info.label = viewer.label;
  }
  return info;
}

function availableViewers(excludeViewerId?: string): SignalViewerInfo[] {
  return [...viewers.values()]
    .filter(
      viewer =>
        viewer.viewerId !== excludeViewerId &&
        viewer.receiveCommand !== undefined,
    )
    .map(viewerInfo);
}

function notifyAvailability(): void {
  for (const viewer of viewers.values()) {
    if (!viewer.availabilityCommand) continue;

    vscode.commands.executeCommand(viewer.availabilityCommand, {
      viewerId: viewer.viewerId,
      availableViewers: availableViewers(viewer.viewerId),
    }).then(
      undefined,
      err => output.appendLine(
        `[SignalViewers] availability notification failed for ${viewer.viewerId}: ${err}`,
      ),
    );
  }
}

function registerSignalViewer(args: RegisterSignalViewerArgs): SignalViewerInfo[] {
  if (!args || typeof args.viewerId !== 'string' || args.viewerId.length === 0) {
    throw new Error('viewerId is required');
  }

  viewers.set(args.viewerId, {
    viewerId: args.viewerId,
    label: args.label,
    receiveCommand: args.receiveCommand,
    availabilityCommand: args.availabilityCommand,
  });

  output.appendLine(`[SignalViewers] registered ${args.viewerId}`);
  notifyAvailability();
  return availableViewers(args.viewerId);
}

function unregisterSignalViewer(args: UnregisterSignalViewerArgs): void {
  if (!args || typeof args.viewerId !== 'string' || args.viewerId.length === 0) {
    return;
  }

  if (viewers.delete(args.viewerId)) {
    output.appendLine(`[SignalViewers] unregistered ${args.viewerId}`);
    notifyAvailability();
  }
}

function getSignalViewers(args?: GetSignalViewersArgs): SignalViewerInfo[] {
  return availableViewers(args?.excludeViewerId);
}

async function sendSignals(args: SendSignalsArgs): Promise<{ delivered: number }> {
  if (!args || typeof args.sourceViewerId !== 'string') {
    throw new Error('sourceViewerId is required');
  }

  const signalPaths = Array.isArray(args.signalPaths)
    ? args.signalPaths.filter(
        (signalPath): signalPath is string =>
          typeof signalPath === 'string' && signalPath.length > 0,
      )
    : [];
  if (signalPaths.length === 0) {
    return { delivered: 0 };
  }

  let delivered = 0;
  for (const viewer of viewers.values()) {
    if (viewer.viewerId === args.sourceViewerId || !viewer.receiveCommand) {
      continue;
    }

    await vscode.commands.executeCommand(viewer.receiveCommand, {
      targetViewerId: viewer.viewerId,
      sourceViewerId: args.sourceViewerId,
      signalPaths,
    });
    delivered++;
  }

  output.appendLine(
    `[SignalViewers] sent ${signalPaths.length} signal(s) from ${args.sourceViewerId} to ${delivered} viewer(s)`,
  );
  return { delivered };
}

export function registerCommands(context: vscode.ExtensionContext): void {
  context.subscriptions.push(
    output,
    vscode.commands.registerCommand(
      'rohd.registerSignalViewer',
      registerSignalViewer,
    ),
    vscode.commands.registerCommand(
      'rohd.unregisterSignalViewer',
      unregisterSignalViewer,
    ),
    vscode.commands.registerCommand('rohd.getSignalViewers', getSignalViewers),
    vscode.commands.registerCommand('rohd.sendSignals', sendSignals),
  );
}

export function dispose(): void {
  viewers.clear();
}