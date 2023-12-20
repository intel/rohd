import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/models/tree_model.dart';

part 'selected_module_provider.g.dart';

@riverpod
class SelectedModule extends _$SelectedModule {
  @override
  TreeModel? build() {
    return null;
  }

  void setModule(TreeModel module) {
    state = module;
  }
}
