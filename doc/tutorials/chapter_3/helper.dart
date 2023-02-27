class FAResult {
  int sum = 0;
  int cOut = 0;
}

FAResult faTruthTable(int a, int b, int cIn) {
  final res = FAResult();
  if (a + b + cIn == 0) {
    return res
      ..sum = 0
      ..cOut = 0;
  } else if (a + b + cIn == 3) {
    return res
      ..sum = 1
      ..cOut = 1;
  } else if (a + b + cIn == 1) {
    return res
      ..sum = 1
      ..cOut = 0;
  } else {
    return res
      ..sum = 0
      ..cOut = 1;
  }
}
