import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/tree_model.dart';

part 'selected_module_state.dart';

class SelectedModuleCubit extends Cubit<SelectedModuleState> {
  SelectedModuleCubit() : super(SelectedModuleInitial());

  void setModule(TreeModel module) {
    emit(SelectedModuleLoaded(module));
  }
}
