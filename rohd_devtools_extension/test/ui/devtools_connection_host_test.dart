// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// devtools_connection_host_test.dart
// Tests for DevTools connection URI and DTD resolution behavior.
//
// 2026 July
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:dtd/dtd.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/devtools_connection_host.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/vm_connection_form.dart';

class _UriNormalizingStrategy extends VmConnectionStrategy {
  @override
  Future<VmConnectionResult> connect(String uri) async =>
      throw UnimplementedError();
}

void main() {
  group('DevToolsConnectionHostState URI cleaning', () {
    test('extracts a VM service URI from surrounding console output', () {
      expect(
        DevToolsConnectionHostState.cleanVmServiceUri(
          'Observatory listening at ws://127.0.0.1:8181/abc=/ws trailing text',
        ),
        'ws://127.0.0.1:8181/abc=/ws',
      );
    });

    test('keeps a VM URI without the standard suffix from its websocket start',
        () {
      expect(
        DevToolsConnectionHostState.cleanVmServiceUri(
          'open wss://host:8181/custom',
        ),
        'wss://host:8181/custom',
      );
    });

    test('extracts DTD URI without stopping at the VM websocket suffix', () {
      expect(
        DevToolsConnectionHostState.cleanDtdUri(
          'ws://host:8181/vm=/ws then ws://host:8181/dtd=',
        ),
        'ws://host:8181/vm=/ws then ws://host:8181/dtd=',
      );
    });
  });

  group('resolveVmConnectionAttempt', () {
    test('uses a valid manually entered VM URI without discovery', () async {
      var discoverCalled = false;

      final resolution = await resolveVmConnectionAttempt(
        rawVmServiceUri: ' ws://host:8181/app=/ws ',
        rawDtdUri: '',
        discoverVmServices: (uri) async {
          discoverCalled = true;
          return const [];
        },
      );

      expect(resolution.vmServiceUri, 'ws://host:8181/app=/ws');
      expect(resolution.error, isNull);
      expect(discoverCalled, isFalse);
    });

    test('discovers and selects the exposed URI of the first VM', () async {
      final resolution = await resolveVmConnectionAttempt(
        rawVmServiceUri: '',
        rawDtdUri: ' ws://host:8181/dtd= ',
        discoverVmServices: (uri) async {
          expect(uri, 'ws://host:8181/dtd=');
          return [
            DiscoveredVmService(
              name: 'counter',
              uri: 'ws://internal:8181/app=/ws',
              exposedUri: 'ws://forwarded:8181/app=/ws',
            ),
          ];
        },
      );

      expect(resolution.vmServiceUri, 'ws://forwarded:8181/app=/ws');
      expect(resolution.error, isNull);
    });

    test('falls back to the raw discovered VM URI when no exposed URI exists',
        () async {
      final resolution = await resolveVmConnectionAttempt(
        rawVmServiceUri: '',
        rawDtdUri: ' ws://host:8181/dtd= ',
        discoverVmServices: (uri) async => [
          DiscoveredVmService(
            name: 'counter',
            uri: 'ws://internal:8181/app=/ws',
          ),
        ],
      );

      expect(resolution.vmServiceUri, 'ws://internal:8181/app=/ws');
      expect(resolution.cleanedDtdUri, 'ws://host:8181/dtd=');
      expect(resolution.error, isNull);
    });

    test('returns a validation error when neither URI is usable', () async {
      final resolution = await resolveVmConnectionAttempt(
        rawVmServiceUri: 'ws://host:8181/xxxx=/ws',
        rawDtdUri: 'not a websocket URI',
        discoverVmServices: (uri) async => const [],
      );

      expect(resolution.vmServiceUri, isNull);
      expect(resolution.error, 'Please enter a VM Service URI or DTD URI');
    });

    test('returns a discovery error when DTD has no VM services', () async {
      final resolution = await resolveVmConnectionAttempt(
        rawVmServiceUri: '',
        rawDtdUri: 'ws://host:8181/dtd=',
        discoverVmServices: (uri) async => const [],
      );

      expect(resolution.vmServiceUri, isNull);
      expect(
        resolution.error,
        'No VM services found via DTD. Is your ROHD app running?',
      );
    });
  });

  group('dtdEventMatchesTrackedVm', () {
    test('matches direct and exposed VM service URIs', () {
      expect(
        dtdEventMatchesTrackedVm(
          trackedVmUri: null,
          eventUri: null,
          eventExposedUri: null,
        ),
        isTrue,
      );
      expect(
        dtdEventMatchesTrackedVm(
          trackedVmUri: 'ws://forwarded:8181/app=/ws',
          eventUri: null,
          eventExposedUri: 'ws://forwarded:8181/app=/ws',
        ),
        isTrue,
      );
      expect(
        dtdEventMatchesTrackedVm(
          trackedVmUri: 'ws://forwarded:8181/app=/ws',
          eventUri: 'ws://internal:8181/app=/ws',
          eventExposedUri: 'ws://forwarded:8181/app=/ws',
        ),
        isTrue,
      );
      expect(
        dtdEventMatchesTrackedVm(
          trackedVmUri: 'ws://one:8181/app=/ws',
          eventUri: 'ws://two:8181/app=/ws',
          eventExposedUri: null,
        ),
        isFalse,
      );
    });
  });

  group('preferredVmServiceUriFromDtdEvent', () {
    test('prefers exposed URI, then raw URI, then null', () {
      expect(
        preferredVmServiceUriFromDtdEvent(
          DTDEvent(
            ConnectedAppServiceConstants.serviceName,
            ConnectedAppServiceConstants.vmServiceRegistered,
            {
              DtdParameters.uri: 'ws://internal:8181/app=/ws',
              DtdParameters.exposedUri: 'ws://forwarded:8181/app=/ws',
            },
            1,
          ),
        ),
        'ws://forwarded:8181/app=/ws',
      );
      expect(
        preferredVmServiceUriFromDtdEvent(
          DTDEvent(
            ConnectedAppServiceConstants.serviceName,
            ConnectedAppServiceConstants.vmServiceRegistered,
            {DtdParameters.uri: 'ws://internal:8181/app=/ws'},
            2,
          ),
        ),
        'ws://internal:8181/app=/ws',
      );
      expect(
        preferredVmServiceUriFromDtdEvent(
          DTDEvent(
            ConnectedAppServiceConstants.serviceName,
            ConnectedAppServiceConstants.vmServiceRegistered,
            const {},
            3,
          ),
        ),
        isNull,
      );
    });
  });

  group('VmConnectionStrategy.normalizeUri', () {
    final strategy = _UriNormalizingStrategy();

    test('converts HTTP URIs to websocket URIs and appends the websocket path',
        () {
      expect(
        strategy.normalizeUri('http://host:8181/debug/'),
        Uri.parse('ws://host:8181/debug/ws'),
      );
      expect(
        strategy.normalizeUri('https://host:8181'),
        Uri.parse('wss://host:8181/ws'),
      );
    });

    test('retains an existing websocket path and rejects invalid URIs', () {
      expect(
        strategy.normalizeUri('ws://host:8181/app=/ws'),
        Uri.parse('ws://host:8181/app=/ws'),
      );
      expect(strategy.normalizeUri('http://[invalid'), isNull);
    });
  });

  group('VmConnectionTransition', () {
    test('classifies state preservation for each connection kind', () {
      const fresh = VmConnectionTransition.fresh();
      const restart = VmConnectionTransition.sameVmRestart();
      const disconnect = VmConnectionTransition.disconnect();

      expect(fresh.preservesAppState, isFalse);
      expect(fresh.isSameLogicalVm, isFalse);
      expect(restart.preservesAppState, isTrue);
      expect(restart.isSameLogicalVm, isTrue);
      expect(disconnect.preservesAppState, isFalse);
      expect(disconnect.kind, VmConnectionTransitionKind.disconnect);
    });

    test('retains captured prior identity when values are not replaced', () {
      final transition =
          (const VmConnectionTransition.sameVmRestart()).withPrevious(
        previousUri: 'ws://host:8181/app=/ws',
        previousIsolateId: 'isolate-1',
        previousVmName: 'counter',
      );

      final copied = transition.withPrevious(previousVmName: 'counter-next');

      expect(copied.previousUri, 'ws://host:8181/app=/ws');
      expect(copied.previousIsolateId, 'isolate-1');
      expect(copied.previousVmName, 'counter-next');
    });
  });
}
