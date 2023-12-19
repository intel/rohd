import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:devtools_app_shared/service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/models/tree_module.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/providers/rohd_service_provider.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/providers/selected_module_provider.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/ui/rohd_appbar.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/ui/tree_page_body.dart';

class RohdDevToolsExtension extends StatelessWidget {
  const RohdDevToolsExtension({super.key});

  @override
  Widget build(BuildContext context) {
    return const DevToolsExtension(
      child: RohdExtensionHomePage(),
    );
  }
}

class RohdExtensionHomePage extends ConsumerStatefulWidget {
  const RohdExtensionHomePage({super.key});

  @override
  ConsumerState<RohdExtensionHomePage> createState() =>
      _RohdExtensionHomePageState();
}

class _RohdExtensionHomePageState extends ConsumerState<RohdExtensionHomePage> {
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
      appBar: const RohdAppBar(),
      body: TreePageBody(
          screenSize: screenSize,
          ref: ref,
          futureModuleTree: futureModuleTree,
          selectedModule: selectedModule),
    );
  }
}
