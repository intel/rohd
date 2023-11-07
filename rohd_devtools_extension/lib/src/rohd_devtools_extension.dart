// Copyright 2023 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// import 'package:devtools_app/devtools_app.dart';
import 'dart:async';
import 'dart:convert';
import 'package:devtools_extensions/api.dart';
import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:devtools_app_shared/service.dart';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:rohd/rohd.dart' as rohd show Module;
import 'package:vm_service/vm_service.dart';
import 'eval.dart';
// import 'package:rohd/src/diagnostics/inspector_service.dart';

class RohdDevToolsExtension extends StatelessWidget {
  const RohdDevToolsExtension({super.key});

  @override
  Widget build(BuildContext context) {
    return const DevToolsExtension(
      child: RohdExtensionHomePage(),
    );
  }
}

class RohdExtensionHomePage extends StatefulWidget {
  const RohdExtensionHomePage({super.key});

  @override
  State<RohdExtensionHomePage> createState() => _RohdExtensionHomePageState();
}

class _RohdExtensionHomePageState extends State<RohdExtensionHomePage> {
  int counter = 0;

  String? message;

  late final EvalOnDartLibrary fooControllerEval;
  late final Disposable evalDisposable;

  static const _defaultEvalResponseText = '--';

  var evalResponseText = _defaultEvalResponseText;

  @override
  void initState() {
    super.initState();
    unawaited(_initEval());

    // TODO(Quek): Init the inspector service
    // rohd.InspectorService();

    // Example of the devtools extension registering a custom handler.
    extensionManager.registerEventHandler(
      DevToolsExtensionEventType.themeUpdate,
      (event) {
        final themeUpdateValue =
            event.data?[ExtensionEventParameters.theme] as String?;
        setState(() {
          message = themeUpdateValue;
        });
      },
    );
  }

  @override
  void dispose() {
    fooControllerEval.dispose();
    evalDisposable.dispose();
    super.dispose();
  }

  Future<void> _initEval() async {
    await serviceManager.onServiceAvailable;
    fooControllerEval = EvalOnDartLibrary(
      // 'package:rohd/src/diagnostics/inspector_service.dart',
      'package:rohd/src/diagnostics/old_service.dart',
      serviceManager.service!,
      serviceManager: serviceManager,
    );
    evalDisposable = Disposable();
  }

  void _incrementCounter() {
    setState(() {
      testCode();
      counter++;
    });
    extensionManager.postMessageToDevTools(
      DevToolsExtensionEvent(
        DevToolsExtensionEventType.unknown,
        data: {'increment_count': counter},
      ),
    );
  }

  Future<void> testCode() async {
    final isAlive = Disposable();
    final treeInstance = await fooControllerEval
        .evalInstance('ModuleTree.instance.stringMod', isAlive: isAlive);

    final thingsListString =
        treeInstance.valueAsString ?? _defaultEvalResponseText;
    final thingsListJSON = json.decode(thingsListString);

    print(thingsListJSON['nested']);
  }

  Future<void> testCodeServiceExtension() async {
    // From Kenzii discord, https://github.com/flutter/devtools/blob/master/packages/devtools_app/lib/src/shared/diagnostics/inspector_service.dart#L1367-L1371

    //////////////////// Working Code //////////////////////////
    // if (serviceManager.serviceExtensionManager
    //     .isServiceExtensionAvailable('ext.rohd.module_tree')) {
    //   final available = await serviceManager.serviceExtensionManager
    //       .waitForServiceExtensionAvailable('ext.rohd.module_tree');
    //   if (!available) {
    //     extensionManager.showNotification('service extension not available');
    //   }
    // } else {
    //   extensionManager.showNotification('cannot find service extension.');
    // }
    // print(serviceManager.isolateManager.mainIsolate.value!.id);
    // final response = await serviceManager.service!.callServiceExtension(
    //   'ext.rohd.module_tree',
    //   isolateId: serviceManager.isolateManager.mainIsolate.value!.id,
    // );
    // final json = response.json!;
    // if (json['errorMessage'] != null) {
    //   throw Exception('ext.rohd.module_tree -- ${json['errorMessage']}');
    // }
    // print('your json is: ');
    // print(json);
    // extensionManager.showNotification('$json');

    print('running test code for service extension.');

    const kServiceExtensionName = 'ext.rohd.module_tree';
    final service = serviceManager.service!;
    final vm = await service.getVM();

    // Iterate over all isolates in the process.
    for (final isolateRef in vm.isolates!) {
      final isolate = await service.getIsolate(isolateRef.id!);
      if (isolate.extensionRPCs!.contains(kServiceExtensionName)) {
        print(
            'Service extension $kServiceExtensionName is registered on ${isolate.name}');
        print(
            'Service extension of ROHD is registered on isolate ID: ${isolate.id!}');
        try {
          // Invoke the extension on each isolate with the service extension registered.
          final response = await service.callServiceExtension(
            kServiceExtensionName,
            isolateId: isolate.id!,
          );
          print('Result from ${isolate.name}: ${response.json}');
          extensionManager.showNotification('${response.json}');
        } catch (e) {
          print('Failed to invoke extension on ${isolate.name}: $e');
        }
      }
    }
    //////////////////////////////////////////////////////////
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('ROHD DevTools Extension'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text('You have pushed the button $counter times'),
            const SizedBox(height: 16.0),
            ElevatedButton(
              onPressed: _incrementCounter,
              child: const Text('Increment and post count to DevTools'),
            ),
            const SizedBox(height: 48.0),
            Text('Received theme update from DevTools: $message'),
            ElevatedButton(
                onPressed: () => testCode(), child: const Text('Quek Btn')),
            const SizedBox(height: 48.0),
            ElevatedButton(
              onPressed: () => extensionManager
                  .showNotification('Yay, DevTools Extensions!'),
              child: const Text('Show DevTools notification'),
            ),
            const SizedBox(height: 16.0),
            ElevatedButton(
              onPressed: () => extensionManager.showBannerMessage(
                key: 'example_message_single_dismiss',
                type: 'warning',
                message: 'Warning: with great power, comes great '
                    'responsibility. I\'m not going to tell you twice.\n'
                    '(This message can only be shown once)',
                extensionName: 'rohd',
              ),
              child: const Text(
                'Show DevTools warning (ignore if already dismissed)',
              ),
            ),
            const SizedBox(height: 16.0),
            ElevatedButton(
              onPressed: () => extensionManager.showBannerMessage(
                key: 'example_message_multi_dismiss',
                type: 'warning',
                message: 'Warning: with great power, comes great '
                    'responsibility. I\'ll keep reminding you if you '
                    'forget.\n(This message can be shown multiple times)',
                extensionName: 'rohd',
                ignoreIfAlreadyDismissed: false,
              ),
              child: const Text(
                'Show DevTools warning (can show again after dismiss)',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
