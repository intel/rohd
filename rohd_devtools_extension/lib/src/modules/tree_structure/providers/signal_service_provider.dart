import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../services/signal_service.dart';

part 'signal_service_provider.g.dart';

@riverpod
SignalService signalService(SignalServiceRef ref) {
  return SignalService();
}
