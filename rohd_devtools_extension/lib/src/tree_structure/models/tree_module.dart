class TreeModule {
  final String name;
  final Map<String, dynamic> inputs;
  final Map<String, dynamic> outputs;
  final List<TreeModule> subModules;

  TreeModule({
    required this.name,
    required this.inputs,
    required this.outputs,
    required this.subModules,
  });

  factory TreeModule.fromJson(Map<String, dynamic> json) {
    return TreeModule(
      name: json['name'],
      inputs: Map<String, dynamic>.from(json['inputs']),
      outputs: Map<String, dynamic>.from(json['outputs']),
      subModules: (json["subModules"] as List)
          .map((subModule) => TreeModule.fromJson(subModule))
          .toList(),
    );
  }
}
