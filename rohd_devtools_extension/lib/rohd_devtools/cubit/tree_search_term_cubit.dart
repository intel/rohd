import 'package:flutter_bloc/flutter_bloc.dart';

class TreeSearchTermCubit extends Cubit<String?> {
  TreeSearchTermCubit() : super(null);

  void setTerm(String term) {
    emit(term);
  }
}
