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
      'package:rohd/src/diagnostics/inspector_service.dart',
      serviceManager.service!,
      serviceManager: serviceManager,
    );
    evalDisposable = Disposable();
  }

  void _incrementCounter() {
    setState(() {
      evalModuleTree();
      counter++;
    });
    extensionManager.postMessageToDevTools(
      DevToolsExtensionEvent(
        DevToolsExtensionEventType.unknown,
        data: {'increment_count': counter},
      ),
    );
  }

  Future<void> evalModuleTree() async {
    final treeInstance = await fooControllerEval.evalInstance(
        'ModuleTree.instance.hierarchyJSON',
        isAlive: evalDisposable);

    final thingsListString =
        treeInstance.valueAsString ?? _defaultEvalResponseText;
    final thingsListJSON = json.decode(thingsListString);

    extensionManager.postMessageToDevTools(
      DevToolsExtensionEvent(
        DevToolsExtensionEventType.unknown,
        data: {'root': thingsListJSON['name']},
      ),
    );

    extensionManager.showBannerMessage(
      key: 'ROHD Hierarchy',
      type: 'warning',
      message: thingsListString,
      extensionName: 'rohd',
    );
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
                onPressed: () => evalModuleTree(),
                child: const Text('Quek Btn')),
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
