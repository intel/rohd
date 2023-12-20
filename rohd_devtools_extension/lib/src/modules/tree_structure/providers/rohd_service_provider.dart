import 'package:devtools_app_shared/service.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/models/tree_model.dart';
import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/providers/signal_service_provider.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/providers/tree_service_provider.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/services/signal_service.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/services/tree_service.dart';

part 'rohd_service_provider.g.dart';

@riverpod
class RohdModuleTree extends _$RohdModuleTree {
  late TreeService treeService;
  late SignalService signalService;
  late EvalOnDartLibrary rohdControllerEval;
  late Disposable evalDisposable;

  @override
  Future<TreeModel> build() {
    _initEval();
    rohdControllerEval = EvalOnDartLibrary(
      'package:rohd/src/diagnostics/inspector_service.dart',
      serviceManager.service!,
      serviceManager: serviceManager,
    );
    evalDisposable = Disposable();

    treeService = ref.read(treeServiceProvider);
    signalService = ref.read(signalServiceProvider);

    return evalModuleTree();
  }

  Future<void> _initEval() async {
    await serviceManager.onServiceAvailable;
  }

  Future<TreeModel> evalModuleTree() {
    return treeService.evalModuleTree();
  }

  void refreshModuleTree() {
    state = const AsyncValue.loading();
    treeService.refreshModuleTree().then((value) {
      state = AsyncValue.data(value);
    }).catchError((error, trace) {
      state = AsyncValue.error(error, trace);
    });
  }
}
