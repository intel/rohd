import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/services/signal_service.dart';

part 'signal_service_provider.g.dart';

@riverpod
SignalService signalService(SignalServiceRef ref) {
  return SignalService();
}
