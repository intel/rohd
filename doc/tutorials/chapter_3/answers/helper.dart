class FSResult {
  int diff = 0;
  int borrowOut = 0;
}

FSResult fsTruthTable(int a, int b, int bIn) {
  final res = FSResult();

  if (a < b + bIn) {
    res
      ..diff = (a + 2) - b - bIn
      ..borrowOut = 1;
  } else {
    res.diff = a - b - bIn;
  }

  return res;
}
