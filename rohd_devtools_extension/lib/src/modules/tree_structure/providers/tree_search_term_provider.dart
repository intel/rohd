import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'tree_search_term_provider.g.dart';

@riverpod
class TreeSearchTerm extends _$TreeSearchTerm {
  @override
  String? build() {
    return null;
  }

  void setTerm(String term) {
    state = term;
  }
}
