import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../services/tree_service.dart';
import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:devtools_app_shared/service.dart';

part 'tree_service_provider.g.dart';

@riverpod
TreeService treeService(TreeServiceRef ref) {
  final rohdControllerEval = EvalOnDartLibrary(
    'package:rohd/src/diagnostics/inspector_service.dart',
    serviceManager.service!,
    serviceManager: serviceManager,
  );
  final evalDisposable = Disposable();
  return TreeService(rohdControllerEval, evalDisposable);
}
