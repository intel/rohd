import 'package:flutter_bloc/flutter_bloc.dart';

class SignalSearchTermCubit extends Cubit<String?> {
  SignalSearchTermCubit() : super(null);

  void setTerm(String term) {
    emit(term);
  }
}
