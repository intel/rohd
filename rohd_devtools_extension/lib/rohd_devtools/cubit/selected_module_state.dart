part of 'selected_module_cubit.dart';

abstract class SelectedModuleState extends Equatable {
  const SelectedModuleState();

  @override
  List<Object?> get props => [];
}

class SelectedModuleInitial extends SelectedModuleState {}

class SelectedModuleLoaded extends SelectedModuleState {
  final TreeModel module;

  const SelectedModuleLoaded(this.module);

  @override
  List<Object?> get props => [module];
}
