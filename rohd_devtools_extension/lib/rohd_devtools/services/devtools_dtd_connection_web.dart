import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:dtd/dtd.dart';
import 'package:flutter/foundation.dart';
import 'package:vm_service/vm_service.dart';

/// DTD connection managed by the containing DevTools application.
ValueListenable<DartToolingDaemon?> get devToolsDtdConnection =>
    dtdManager.connection;

/// VM service managed by the containing DevTools application.
VmService? get devToolsVmService => serviceManager.service;

/// Main isolate managed by the containing DevTools application.
String? get devToolsMainIsolateId =>
    serviceManager.isolateManager.mainIsolate.value?.id;
