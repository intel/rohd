class SynthFileContents {
  final String name;
  final String? description;
  final String contents;

  const SynthFileContents(
      {required this.name, required this.contents, this.description});

  @override
  String toString() => contents;
}
