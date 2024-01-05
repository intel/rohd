import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:devtools_app_shared/service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/models/tree_model.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/providers/rohd_service_provider.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/providers/selected_module_provider.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/ui/devtool_appbar.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/view/tree_structure_page.dart';
import 'package:rohd_devtools_extension/src/modules/waveform_viewer/view/waveform_viewer_page.dart';

class RohdDevToolsModule extends StatelessWidget {
  const RohdDevToolsModule({super.key});

  @override
  Widget build(BuildContext context) {
    return const DevToolsExtension(
      child: RohdExtensionModule(),
    );
  }
}

class RohdExtensionModule extends ConsumerStatefulWidget {
  const RohdExtensionModule({super.key});

  @override
  ConsumerState<RohdExtensionModule> createState() =>
      _RohdExtensionModuleState();
}

class _RohdExtensionModuleState extends ConsumerState<RohdExtensionModule> {
  late final EvalOnDartLibrary rohdControllerEval;

  late AsyncValue<TreeModel> futureModuleTree;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    futureModuleTree = ref.watch(rohdModuleTreeProvider);
  }

  @override
  Widget build(BuildContext context) {
    final selectedModule = ref.watch(selectedModuleProvider);
    final AsyncValue<TreeModel> futureModuleTree =
        ref.watch(rohdModuleTreeProvider);
    final screenSize = MediaQuery.of(context).size;

    return Scaffold(
      appBar: const DevtoolAppBar(),
      // body: TreeStructurePage(
      //   screenSize: screenSize,
      //   futureModuleTree: futureModuleTree,
      //   selectedModule: selectedModule,
      // ),
      body: WaveformView(),
    );
  }
}
